defmodule Ysc.Accounts.VerificationCodesTest do
  @moduledoc """
  Comprehensive coverage for the shared email/SMS OTP API used by account setup,
  settings, and post-migration onboarding.
  """
  use Ysc.DataCase, async: true

  import Ecto.Query
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.VerificationCodes
  alias Ysc.Repo
  alias Ysc.VerificationCode
  alias Ysc.VerificationCache

  setup do
    user = user_fixture(%{phone_number: unique_user_phone()})
    {:ok, user: user}
  end

  # ---------------------------------------------------------------------------
  # Constants / generation
  # ---------------------------------------------------------------------------

  describe "defaults" do
    test "default_ttl_seconds/0 is 10 minutes" do
      assert VerificationCodes.default_ttl_seconds() == 600
    end

    test "resend_seconds/0 is 60" do
      assert VerificationCodes.resend_seconds() == 60
    end
  end

  describe "generate_code/0" do
    test "returns a 6-digit numeric string" do
      code = VerificationCodes.generate_code()
      assert String.length(code) == 6
      assert code =~ ~r/^\d{6}$/
    end

    test "zero-pads short values" do
      # Statistical: many codes will need padding; assert format holds across samples
      for _ <- 1..50 do
        code = VerificationCodes.generate_code()
        assert code =~ ~r/^\d{6}$/
      end
    end

    test "produces varied codes across invocations" do
      codes = MapSet.new(for _ <- 1..20, do: VerificationCodes.generate_code())
      assert MapSet.size(codes) > 1
    end
  end

  # ---------------------------------------------------------------------------
  # OTP input normalization / format
  # ---------------------------------------------------------------------------

  describe "normalize_otp_input/1" do
    test "joins string-keyed map digits in index order and ignores unused keys" do
      assert VerificationCodes.normalize_otp_input(%{
               "0" => "1",
               "1" => "2",
               "_unused_2" => "9",
               "2" => "3",
               "3" => "4",
               "4" => "5",
               "5" => "6"
             }) == "123456"
    end

    test "supports integer map keys from OTP paste" do
      assert VerificationCodes.normalize_otp_input(%{
               0 => "9",
               1 => "8",
               2 => "7",
               3 => "6",
               4 => "5",
               5 => "4"
             }) == "987654"
    end

    test "drops empty digit slots from maps and lists" do
      assert VerificationCodes.normalize_otp_input(%{
               "0" => "1",
               "1" => "",
               "2" => "3",
               "3" => "4",
               "4" => "5",
               "5" => "6"
             }) == "13456"

      assert VerificationCodes.normalize_otp_input([
               "1",
               "",
               "3",
               nil,
               "5",
               "6"
             ]) ==
               "1356"
    end

    test "passes through binaries and returns empty string for other types" do
      assert VerificationCodes.normalize_otp_input("654321") == "654321"
      assert VerificationCodes.normalize_otp_input(nil) == ""
      assert VerificationCodes.normalize_otp_input(123_456) == ""
      assert VerificationCodes.normalize_otp_input(:otp) == ""
    end
  end

  describe "valid_otp_format?/1" do
    test "accepts exactly six digits" do
      assert VerificationCodes.valid_otp_format?("000000")
      assert VerificationCodes.valid_otp_format?("123456")
      assert VerificationCodes.valid_otp_format?("999999")
    end

    test "rejects incomplete, oversized, or non-digit values" do
      refute VerificationCodes.valid_otp_format?("12345")
      refute VerificationCodes.valid_otp_format?("1234567")
      refute VerificationCodes.valid_otp_format?("12a456")
      refute VerificationCodes.valid_otp_format?("")
      refute VerificationCodes.valid_otp_format?(nil)
      refute VerificationCodes.valid_otp_format?(123_456)
      refute VerificationCodes.valid_otp_format?(%{"0" => "1"})
    end
  end

  # ---------------------------------------------------------------------------
  # Storage primitives
  # ---------------------------------------------------------------------------

  describe "store/4, get/2, remove/2, generate_and_store/3" do
    test "store and get roundtrip for email and phone", %{user: user} do
      assert :ok = VerificationCodes.store(user, :email, "111111")
      assert :ok = VerificationCodes.store(user, :phone, "222222")

      assert VerificationCodes.get(user, :email) == "111111"
      assert VerificationCodes.get(user, :phone) == "222222"
    end

    test "get/2 returns nil when missing or expired", %{user: user} do
      assert VerificationCodes.get(user, :email) == nil

      assert :ok = VerificationCodes.store(user, :email, "333333", -1)
      assert VerificationCodes.get(user, :email) == nil
    end

    test "remove/2 clears a stored code", %{user: user} do
      assert :ok = VerificationCodes.store(user, :phone, "444444")
      assert :ok = VerificationCodes.remove(user, :phone)
      assert VerificationCodes.get(user, :phone) == nil
    end

    test "generate_and_store/3 returns a stored code without sending", %{
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        code = VerificationCodes.generate_and_store(user, :email)
        assert code =~ ~r/^\d{6}$/
        assert VerificationCodes.get(user, :email) == code
        refute_enqueued(worker: YscWeb.Workers.EmailNotifier)
        refute_enqueued(worker: YscWeb.Workers.SmsNotifier)
      end)
    end

    test "store replaces an existing code for the same channel", %{user: user} do
      assert :ok = VerificationCodes.store(user, :email, "111111")
      assert :ok = VerificationCodes.store(user, :email, "999999")
      assert VerificationCodes.get(user, :email) == "999999"
    end

    test "email and phone codes for the same user are independent", %{
      user: user
    } do
      assert :ok = VerificationCodes.store(user, :email, "111111")
      assert :ok = VerificationCodes.store(user, :phone, "222222")

      assert :ok = VerificationCodes.remove(user, :email)
      assert VerificationCodes.get(user, :email) == nil
      assert VerificationCodes.get(user, :phone) == "222222"
    end

    test "codes for different users do not collide" do
      user_a = user_fixture(%{phone_number: unique_user_phone()})
      user_b = user_fixture(%{phone_number: unique_user_phone()})

      assert :ok = VerificationCodes.store(user_a, :email, "111111")
      assert :ok = VerificationCodes.store(user_b, :email, "222222")

      assert VerificationCodes.get(user_a, :email) == "111111"
      assert VerificationCodes.get(user_b, :email) == "222222"
    end

    test "stored codes are encrypted at rest", %{user: user} do
      assert :ok = VerificationCodes.store(user, :email, "555555")

      %{rows: [[ciphertext]]} =
        Ecto.Adapters.SQL.query!(
          Repo,
          "SELECT code FROM verification_codes WHERE user_id = $1 AND code_type = $2",
          [user.id, "email_verification"]
        )

      # Raw DB column must not be plaintext
      refute ciphertext == "555555"
      refute ciphertext == <<"555555">>

      # Schema decrypts on load
      record =
        Repo.one!(
          from c in VerificationCode,
            where: c.user_id == ^user.id and c.code_type == "email_verification"
        )

      assert record.code == "555555"
    end
  end

  # ---------------------------------------------------------------------------
  # Delivery
  # ---------------------------------------------------------------------------

  describe "deliver/4" do
    test "schedules email to the user's address with suffix in idempotency key",
         %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert %Oban.Job{} =
                 VerificationCodes.deliver(user, :email, "123456",
                   suffix: "manual1"
                 )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => user.email,
            "idempotency_key" =>
              "account_setup_verification_#{user.id}_manual1",
            "template" => "account_setup_verification"
          }
        )
      end)
    end

    test "schedules email to an override destination", %{user: user} do
      other = unique_user_email()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert %Oban.Job{} =
                 VerificationCodes.deliver(user, :email, "123456",
                   to: other,
                   suffix: "override"
                 )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => other,
            "idempotency_key" =>
              "account_setup_verification_#{user.id}_override",
            "template" => "account_setup_verification"
          }
        )
      end)
    end

    test "schedules SMS to override phone with suffix in idempotency key", %{
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Oban.Job{}} =
                 VerificationCodes.deliver(user, :phone, "999999",
                   to: "+12065550999",
                   suffix: "sms2"
                 )

        assert_enqueued(
          worker: YscWeb.Workers.SmsNotifier,
          args: %{
            "phone_number" => "12065550999",
            "idempotency_key" => "phone_verification_#{user.id}_sms2",
            "template" => "phone_verification"
          }
        )
      end)
    end

    test "schedules SMS to the user's phone number by default", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Oban.Job{}} =
                 VerificationCodes.deliver(user, :phone, "999999",
                   suffix: "sms_default"
                 )

        jobs = all_enqueued(worker: YscWeb.Workers.SmsNotifier)

        assert Enum.any?(jobs, fn job ->
                 job.args["idempotency_key"] ==
                   "phone_verification_#{user.id}_sms_default" and
                   job.args["template"] == "phone_verification" and
                   is_binary(job.args["phone_number"]) and
                   job.args["phone_number"] != ""
               end)
      end)
    end

    test "omits underscore suffix when suffix is nil", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert %Oban.Job{} = VerificationCodes.deliver(user, :email, "123456")

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "idempotency_key" => "account_setup_verification_#{user.id}"
          }
        )
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # issue / ensure
  # ---------------------------------------------------------------------------

  describe "issue/3" do
    test "issues email code, stores it, and enqueues delivery", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok,
                %{
                  code: code,
                  sent?: true,
                  reused?: false,
                  disabled_until: nil
                }} =
                 VerificationCodes.issue(user, :email, suffix: "test_issue")

        assert code =~ ~r/^\d{6}$/
        assert VerificationCodes.get(user, :email) == code

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => user.email,
            "idempotency_key" =>
              "account_setup_verification_#{user.id}_test_issue",
            "template" => "account_setup_verification"
          }
        )
      end)
    end

    test "issues phone code to an override destination", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %{code: code, sent?: true, reused?: false}} =
                 VerificationCodes.issue(user, :phone,
                   to: "+12065550111",
                   suffix: "phone_override"
                 )

        assert_enqueued(
          worker: YscWeb.Workers.SmsNotifier,
          args: %{
            "phone_number" => "12065550111",
            "idempotency_key" => "phone_verification_#{user.id}_phone_override",
            "template" => "phone_verification"
          }
        )

        assert VerificationCodes.get(user, :phone) == code
      end)
    end

    test "always generates a new code, replacing any previous one", %{
      user: user
    } do
      assert {:ok, %{code: first}} =
               VerificationCodes.issue(user, :email, suffix: "a")

      assert {:ok, %{code: second, reused?: false}} =
               VerificationCodes.issue(user, :email, suffix: "b")

      assert first != second
      assert VerificationCodes.get(user, :email) == second
    end

    test "default delivery suffixes are unique across rapid successive issues",
         %{
           user: user
         } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = VerificationCodes.issue(user, :email)
        assert {:ok, _} = VerificationCodes.issue(user, :email)

        jobs =
          all_enqueued(worker: YscWeb.Workers.EmailNotifier)
          |> Enum.filter(&(&1.args["template"] == "account_setup_verification"))

        assert length(jobs) == 2

        keys = Enum.map(jobs, & &1.args["idempotency_key"])
        assert Enum.uniq(keys) == keys
        assert Enum.all?(keys, &String.contains?(&1, "issue_"))
      end)
    end

    test "honors custom ttl", %{user: user} do
      assert {:ok, %{code: code}} =
               VerificationCodes.issue(user, :email, ttl: -1, suffix: "expired")

      # Expired immediately — verify reports :expired and clears the row
      assert {:error, :expired} =
               VerificationCache.verify_code(
                 user.id,
                 :email_verification,
                 code
               )

      assert VerificationCodes.get(user, :email) == nil
    end

    test "rejects unsupported channels", %{user: user} do
      # Use apply/3 so gradual typing does not reject the invalid atom at compile time.
      invalid_channel = List.first([:sms])

      assert_raise FunctionClauseError, fn ->
        apply(VerificationCodes, :issue, [user, invalid_channel, []])
      end
    end
  end

  describe "ensure/3" do
    test "issues and sends when no code exists", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %{code: code, reused?: false, sent?: true}} =
                 VerificationCodes.ensure(user, :email)

        assert VerificationCodes.get(user, :email) == code

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "idempotency_key" => "account_setup_verification_#{user.id}_initial"
          }
        )
      end)
    end

    test "reuses an existing unexpired code without sending again", %{
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %{code: code}} =
                 VerificationCodes.issue(user, :email, suffix: "first")

        refute_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "idempotency_key" => "account_setup_verification_#{user.id}_second"
          }
        )

        jobs_before = length(all_enqueued(worker: YscWeb.Workers.EmailNotifier))

        assert {:ok, %{code: ^code, reused?: true, sent?: false}} =
                 VerificationCodes.ensure(user, :email, suffix: "second")

        jobs_after = length(all_enqueued(worker: YscWeb.Workers.EmailNotifier))
        assert jobs_after == jobs_before
      end)
    end

    test "issues a new code when the previous one expired", %{user: user} do
      assert :ok = VerificationCodes.store(user, :phone, "111111", -1)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %{code: code, reused?: false, sent?: true}} =
                 VerificationCodes.ensure(user, :phone, suffix: "after_expiry")

        assert code != "111111"
        assert VerificationCodes.get(user, :phone) == code

        assert_enqueued(
          worker: YscWeb.Workers.SmsNotifier,
          args: %{
            "idempotency_key" => "phone_verification_#{user.id}_after_expiry"
          }
        )
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # resend
  # ---------------------------------------------------------------------------

  describe "resend/3" do
    test "reuses existing email code, sends again, and sets disabled_until", %{
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %{code: code}} =
                 VerificationCodes.issue(user, :email, suffix: "seed")

        assert {:ok,
                %{
                  code: ^code,
                  reused?: true,
                  sent?: true,
                  disabled_until: %DateTime{} = until
                }} = VerificationCodes.resend(user, :email)

        assert DateTime.compare(until, DateTime.utc_now()) == :gt

        jobs = all_enqueued(worker: YscWeb.Workers.EmailNotifier)

        assert Enum.any?(jobs, fn job ->
                 String.contains?(
                   job.args["idempotency_key"],
                   "resend_existing_"
                 )
               end)
      end)
    end

    test "generates a new phone code when none exists", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok,
                %{
                  code: code,
                  reused?: false,
                  sent?: true,
                  disabled_until: %DateTime{}
                }} = VerificationCodes.resend(user, :phone)

        assert code =~ ~r/^\d{6}$/
        assert VerificationCodes.get(user, :phone) == code

        jobs = all_enqueued(worker: YscWeb.Workers.SmsNotifier)

        assert Enum.any?(jobs, fn job ->
                 String.contains?(job.args["idempotency_key"], "resend_new_")
               end)
      end)
    end

    test "honors destination override on resend", %{user: user} do
      other = unique_user_email()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} =
                 VerificationCodes.resend(user, :email, to: other)

        jobs = all_enqueued(worker: YscWeb.Workers.EmailNotifier)
        assert Enum.any?(jobs, &(&1.args["recipient"] == other))
      end)
    end

    test "custom rate_limit_seconds is reflected in disabled_until", %{
      user: user
    } do
      assert {:ok, %{disabled_until: until}} =
               VerificationCodes.resend(user, :email, rate_limit_seconds: 120)

      diff = DateTime.diff(until, DateTime.utc_now(), :second)
      assert diff in 115..125
    end
  end

  # ---------------------------------------------------------------------------
  # verify / verify_unchecked
  # ---------------------------------------------------------------------------

  describe "verify/3" do
    test "verifies a matching email code and consumes it", %{user: user} do
      assert {:ok, %{code: code}} =
               VerificationCodes.issue(user, :email, suffix: "v1")

      assert {:ok, :verified} = VerificationCodes.verify(user, :email, code)
      assert VerificationCodes.get(user, :email) == nil
    end

    test "verifies a matching phone code and consumes it", %{user: user} do
      assert {:ok, %{code: code}} =
               VerificationCodes.issue(user, :phone, suffix: "v2")

      assert {:ok, :verified} = VerificationCodes.verify(user, :phone, code)
      assert VerificationCodes.get(user, :phone) == nil
    end

    test "accepts OTP map input", %{user: user} do
      assert :ok = VerificationCodes.store(user, :email, "135790")

      assert {:ok, :verified} =
               VerificationCodes.verify(user, :email, %{
                 "0" => "1",
                 "1" => "3",
                 "2" => "5",
                 "3" => "7",
                 "4" => "9",
                 "5" => "0"
               })
    end

    test "returns :invalid_code without consuming the stored code", %{
      user: user
    } do
      assert :ok = VerificationCodes.store(user, :email, "123456")

      assert {:error, :invalid_code} =
               VerificationCodes.verify(user, :email, "000001")

      assert VerificationCodes.get(user, :email) == "123456"
    end

    test "returns :not_found when no code is stored", %{user: user} do
      assert {:error, :not_found} =
               VerificationCodes.verify(user, :email, "123456")
    end

    test "returns :expired for expired codes and removes them", %{user: user} do
      assert :ok = VerificationCodes.store(user, :phone, "123456", -1)

      assert {:error, :expired} =
               VerificationCodes.verify(user, :phone, "123456")

      assert VerificationCodes.get(user, :phone) == nil
    end

    test "accepts 000000 in non-prod and clears any stored code", %{user: user} do
      assert :ok = VerificationCodes.store(user, :email, "123456")
      assert {:ok, :verified} = VerificationCodes.verify(user, :email, "000000")
      assert VerificationCodes.get(user, :email) == nil
    end

    test "accepts 000000 even when no code was stored", %{user: user} do
      assert {:ok, :verified} = VerificationCodes.verify(user, :phone, "000000")
    end

    test "email and phone attempt rate limits are independent", %{user: user} do
      assert :ok = VerificationCodes.store(user, :email, "123456")
      assert :ok = VerificationCodes.store(user, :phone, "654321")

      exhaust_verify_attempts(user, :email)

      assert {:error, :rate_limited} =
               VerificationCodes.verify(user, :email, "123456")

      # Phone channel still allowed
      assert {:ok, :verified} =
               VerificationCodes.verify(user, :phone, "654321")
    end

    test "returns :rate_limited after too many attempts on a channel", %{
      user: user
    } do
      VerificationCodes.store(user, :email, "123456")

      exhaust_verify_attempts(user, :email)

      assert {:error, :rate_limited} =
               VerificationCodes.verify(user, :email, "123456")
    end

    test "wrong-length codes do not match via secure_compare crash", %{
      user: user
    } do
      assert :ok = VerificationCodes.store(user, :email, "123456")

      assert {:error, :invalid_code} =
               VerificationCodes.verify(user, :email, "12345")

      assert {:error, :invalid_code} =
               VerificationCodes.verify(user, :email, "1234567")
    end
  end

  describe "verify_unchecked/3" do
    test "verifies without counting toward attempt rate limit", %{user: user} do
      assert :ok = VerificationCodes.store(user, :email, "123456")

      exhaust_verify_attempts(user, :email)

      assert {:error, :rate_limited} =
               VerificationCodes.verify(user, :email, "123456")

      # Unchecked path still works
      assert {:ok, :verified} =
               VerificationCodes.verify_unchecked(user, :email, "123456")
    end

    test "still enforces code validity", %{user: user} do
      assert :ok = VerificationCodes.store(user, :phone, "123456")

      assert {:error, :invalid_code} =
               VerificationCodes.verify_unchecked(user, :phone, "999999")
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-node / shared storage semantics
  # ---------------------------------------------------------------------------

  describe "shared Postgres storage" do
    test "codes are readable from another process", %{user: user} do
      assert {:ok, %{code: code}} =
               VerificationCodes.issue(user, :email, suffix: "shared")

      task =
        Task.async(fn ->
          VerificationCodes.get(user, :email)
        end)

      assert Task.await(task) == code
    end

    test "verify from another process consumes the code", %{user: user} do
      assert {:ok, %{code: code}} =
               VerificationCodes.issue(user, :phone, suffix: "shared_verify")

      task =
        Task.async(fn ->
          VerificationCodes.verify_unchecked(user, :phone, code)
        end)

      assert {:ok, :verified} = Task.await(task)
      assert VerificationCodes.get(user, :phone) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts compatibility wrappers
  # ---------------------------------------------------------------------------

  describe "Accounts wrappers delegate correctly" do
    alias Ysc.Accounts

    test "generate/store/get/verify/remove email helpers", %{user: user} do
      code = Accounts.generate_and_store_email_verification_code(user)
      assert Accounts.get_email_verification_code(user) == code

      assert Accounts.verify_email_verification_code(user, code) ==
               {:ok, :verified}

      assert Accounts.get_email_verification_code(user) == nil

      Accounts.store_email_verification_code(user, "424242")
      assert Accounts.get_email_verification_code(user) == "424242"
      assert :ok = Accounts.remove_email_verification_code(user)
      assert Accounts.get_email_verification_code(user) == nil
    end

    test "generate/store/verify phone helpers", %{user: user} do
      code = Accounts.generate_and_store_phone_verification_code(user)

      assert Accounts.verify_phone_verification_code(user, code) ==
               {:ok, :verified}

      Accounts.store_phone_verification_code(user, "787878")

      assert Accounts.verify_phone_verification_code(user, "787878") ==
               {:ok, :verified}
    end

    test "send_* helpers enqueue with the provided code destination", %{
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        other = unique_user_email()

        Accounts.send_email_verification_code(
          user,
          "123456",
          "wrap1",
          other
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "recipient" => other,
            "idempotency_key" => "account_setup_verification_#{user.id}_wrap1",
            "template" => "account_setup_verification"
          }
        )

        Accounts.send_phone_verification_code(
          user,
          "999999",
          "wrap2",
          "+12065550888"
        )

        assert_enqueued(
          worker: YscWeb.Workers.SmsNotifier,
          args: %{
            "phone_number" => "12065550888",
            "idempotency_key" => "phone_verification_#{user.id}_wrap2",
            "template" => "phone_verification"
          }
        )
      end)
    end
  end

  # Hammer's 1-minute window can roll over mid-loop, so keep attempting
  # until we actually get :rate_limited rather than assuming `limit`
  # consecutive hits land in the same bucket.
  defp exhaust_verify_attempts(user, channel) do
    limit =
      Application.get_env(:ysc, Ysc.EmailVerificationRateLimit, [])[
        :attempt_limit_per_minute
      ] || 12

    assert Enum.any?(1..(limit * 3), fn _ ->
             case VerificationCodes.verify(user, channel, "000001") do
               {:error, :rate_limited} -> true
               {:error, :invalid_code} -> false
               other -> flunk("unexpected verify result: #{inspect(other)}")
             end
           end)
  end
end

defmodule Ysc.Accounts.VerificationCodesResendRateLimitTest do
  @moduledoc false

  # Resend throttling uses the shared :ysc_cache. Other async tests call
  # Cachex.clear/1 and can wipe rate-limit keys between resend calls.
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.VerificationCodes
  alias Ysc.ResendRateLimiter

  setup do
    user = user_fixture(%{phone_number: unique_user_phone()})

    for type <- [:email, :sms] do
      Cachex.del(:ysc_cache, ResendRateLimiter.cache_key(user.id, type))
    end

    on_exit(fn ->
      for type <- [:email, :sms] do
        Cachex.del(:ysc_cache, ResendRateLimiter.cache_key(user.id, type))
      end
    end)

    {:ok, user: user}
  end

  test "rate limits a second resend on the same channel", %{user: user} do
    assert {:ok, _} = VerificationCodes.resend(user, :email)

    assert {:error, :rate_limited, remaining} =
             VerificationCodes.resend(user, :email)

    assert is_integer(remaining)
    assert remaining > 0
  end

  test "email and phone resend rate limits are independent", %{user: user} do
    assert {:ok, _} = VerificationCodes.resend(user, :email)
    assert {:ok, _} = VerificationCodes.resend(user, :phone)
    assert {:error, :rate_limited, _} = VerificationCodes.resend(user, :email)
    assert {:error, :rate_limited, _} = VerificationCodes.resend(user, :phone)
  end
end
