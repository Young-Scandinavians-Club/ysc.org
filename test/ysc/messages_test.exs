defmodule Ysc.MessagesTest do
  @moduledoc """
  Tests for Ysc.Messages context module.

  Idempotency contract:
  - A (message_type, idempotency_key, message_template) triplet must produce
    exactly ONE send regardless of how many times the function is called.
  - The pre-check path (record already exists) must short-circuit before
    touching the mailer / SMS client.
  - Keys are scoped: same key with a different template, or same key with a
    different message_type, are treated as independent sends.
  """
  use Ysc.DataCase, async: true

  import Ecto.Query
  import Swoosh.TestAssertions

  alias Ysc.Messages
  alias Ysc.Messages.MessageIdempotency
  alias Ysc.SmsRateLimit
  import Ysc.AccountsFixtures

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Builds a minimal Swoosh email struct suitable for use with run_send_message_idempotent.
  defp test_email(opts \\ []) do
    recipient = Keyword.get(opts, :to, "test@example.com")
    subj = Keyword.get(opts, :subject, "Test Subject")

    Swoosh.Email.new()
    |> Swoosh.Email.to(recipient)
    |> Swoosh.Email.from({"YSC Test", "noreply@ysc.org"})
    |> Swoosh.Email.subject(subj)
    |> Swoosh.Email.html_body("<p>Test body</p>")
    |> Swoosh.Email.text_body("Test body")
  end

  # Builds attrs for run_send_message_idempotent.
  defp email_attrs(key, template \\ "booking_confirmation", user_id \\ nil) do
    %{
      message_type: :email,
      idempotency_key: key,
      message_template: template,
      params: %{},
      email: "test@example.com",
      rendered_message: "<p>Test body</p>",
      user_id: user_id
    }
  end

  # Builds attrs for run_send_sms_idempotent.
  defp sms_attrs(key, template \\ "booking_checkin_reminder", user_id \\ nil) do
    %{
      message_type: :sms,
      idempotency_key: key,
      message_template: template,
      params: %{},
      phone_number: "12065551234",
      rendered_message: "[YSC] Test SMS message.",
      user_id: user_id
    }
  end

  # NANP digits only (no "+") for attrs.phone_number — matches typical DB/idempotency storage.
  defp sms_attrs_phone(
         key,
         phone,
         template \\ "booking_checkin_reminder",
         user_id \\ nil
       ) do
    phone_digits =
      phone
      |> to_string()
      |> String.trim()
      |> String.trim_leading("+")

    sms_attrs(key, template, user_id) |> Map.put(:phone_number, phone_digits)
  end

  # Counts idempotency records for a given key.
  defp count_records_for_key(key) do
    Ysc.Repo.one(
      from m in MessageIdempotency,
        where: m.idempotency_key == ^key,
        select: count()
    )
  end

  # ---------------------------------------------------------------------------
  # run_send_message_idempotent/2  (email)
  # ---------------------------------------------------------------------------

  describe "run_send_message_idempotent/2 - first-time send" do
    test "sends the email and creates exactly one idempotency record" do
      key = "em_first_#{System.unique_integer()}"

      assert {:ok, _email} =
               Messages.run_send_message_idempotent(
                 test_email(),
                 email_attrs(key)
               )

      assert_email_sent(subject: "Test Subject")
      assert count_records_for_key(key) == 1
    end

    test "succeeds when SES configuration set is configured (tracking metadata path)" do
      prev = Application.get_env(:ysc, :ses_configuration_set)

      Application.put_env(:ysc, :ses_configuration_set, "test-ses-config-set")

      on_exit(fn ->
        if prev == nil do
          Application.delete_env(:ysc, :ses_configuration_set)
        else
          Application.put_env(:ysc, :ses_configuration_set, prev)
        end
      end)

      key = "em_ses_" <> Ecto.UUID.generate()

      template =
        "ses_tracking_" <> Integer.to_string(System.unique_integer([:positive]))

      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-test-ses-#{key}",
          [:ysc, :email, :sent],
          fn _event, _measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:telemetry_email_sent, key, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      edition_id = "01HM1234567890ABCDEFGH"
      subscriber_id = "01HM9876543210ZYXWVUTS"
      user = user_fixture()

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 test_email(),
                 email_attrs(key, template, user.id)
                 |> Map.put(:edition_id, edition_id)
                 |> Map.put(:subscriber_id, subscriber_id)
               )

      assert_receive {:email, delivered}, 3_000

      tags = delivered.provider_options[:tags] || []

      assert Enum.any?(
               tags,
               &(&1[:name] == "edition_id" and &1[:value] == edition_id)
             )

      assert Enum.any?(
               tags,
               &(&1[:name] == "subscriber_id" and &1[:value] == subscriber_id)
             )

      assert Enum.any?(
               tags,
               &(&1[:name] == "user_id" and &1[:value] == to_string(user.id))
             )

      assert_receive {:telemetry_email_sent, ^key, meta}, 3_000
      assert meta.template == template
      assert meta.idempotency_key == key
      assert meta.recipient == "test@example.com"
    end

    test "record contains the correct fields" do
      key = "em_fields_#{System.unique_integer()}"
      template = "booking_confirmation"

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 test_email(),
                 email_attrs(key, template)
               )

      record = Ysc.Repo.get_by(MessageIdempotency, idempotency_key: key)
      assert record.message_type == :email
      assert record.message_template == template
      assert record.email == "test@example.com"
    end

    test "accepts tuple recipient and reports canonical email in telemetry metadata" do
      key = "em_tuple_#{System.unique_integer()}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-test-tuple-#{key}",
          [:ysc, :email, :sent],
          fn _event, _measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:telemetry_email_sent_tuple, key, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      email =
        test_email(to: {"Display Name", "tuple-recipient@example.com"})

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 email,
                 email_attrs(key)
               )

      assert_receive {:telemetry_email_sent_tuple, ^key, meta}, 3_000
      assert meta.recipient == "tuple-recipient@example.com"
    end

    test "uses first address when recipient is a list of emails (telemetry metadata)" do
      key = "em_list_#{System.unique_integer()}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-test-list-#{key}",
          [:ysc, :email, :sent],
          fn _event, _measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:telemetry_email_sent_list, key, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      email =
        test_email(to: ["list-first@example.com", "list-second@example.com"])

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 email,
                 email_attrs(key)
               )

      assert_receive {:telemetry_email_sent_list, ^key, meta}, 3_000
      assert meta.recipient == "list-first@example.com"
    end

    test "empty recipient list uses inspect fallback in telemetry metadata" do
      key = "em_empty_to_#{System.unique_integer()}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-test-empty-to-#{key}",
          [:ysc, :email, :sent],
          fn _event, _measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:telemetry_email_sent_empty_to, key, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 test_email(to: []),
                 email_attrs(key)
               )

      assert_receive {:telemetry_email_sent_empty_to, ^key, meta}, 3_000
      assert meta.recipient == "[]"
    end

    test "recipient list starting with nil resolves to \"nil\" in telemetry metadata" do
      key = "em_nil_head_#{System.unique_integer()}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-nil-head-#{key}",
          [:ysc, :email, :sent],
          fn _event, _measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:telemetry_nil_head, key, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      email =
        test_email()
        |> Map.put(:to, [nil, "fallback@example.com"])

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 email,
                 email_attrs(key)
               )

      assert_receive {:telemetry_nil_head, ^key, meta}, 3_000
      assert meta.recipient == "nil"
    end
  end

  describe "run_send_message_idempotent/2 - duplicate handling" do
    test "duplicate send includes duplicate: true in email :sent telemetry metadata" do
      key = "em_dup_telemetry_#{System.unique_integer()}"
      email = test_email()
      attrs = email_attrs(key)
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-dup-meta-#{key}",
          [:ysc, :email, :sent],
          fn _event, _measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:email_sent_dup_flag, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:ok, _} = Messages.run_send_message_idempotent(email, attrs)
      assert {:ok, _} = Messages.run_send_message_idempotent(email, attrs)

      assert_receive {:email_sent_dup_flag, first_meta}, 3_000
      refute first_meta[:duplicate] == true

      assert_receive {:email_sent_dup_flag, second_meta}, 3_000
      assert second_meta[:duplicate] == true
    end

    test "second call with the same key returns {:ok, email} without sending" do
      key = "em_dup_#{System.unique_integer()}"
      email = test_email()
      attrs = email_attrs(key)

      # First send – email delivered, record committed.
      assert {:ok, _} = Messages.run_send_message_idempotent(email, attrs)
      assert_email_sent(subject: "Test Subject")

      # Second send – pre-check fires, Mailer is never called.
      assert {:ok, _} = Messages.run_send_message_idempotent(email, attrs)
      assert_no_email_sent()
    end

    test "exactly one record exists after any number of duplicate calls" do
      key = "em_one_rec_#{System.unique_integer()}"
      email = test_email()
      attrs = email_attrs(key)

      for _ <- 1..4 do
        assert {:ok, _} = Messages.run_send_message_idempotent(email, attrs)
      end

      assert count_records_for_key(key) == 1
    end

    test "both first and duplicate calls return the email struct" do
      key = "em_ret_#{System.unique_integer()}"
      email = test_email()
      attrs = email_attrs(key)

      {:ok, r1} = Messages.run_send_message_idempotent(email, attrs)
      {:ok, r2} = Messages.run_send_message_idempotent(email, attrs)

      assert r1.subject == "Test Subject"
      assert r2.subject == "Test Subject"
    end
  end

  describe "run_send_message_idempotent/2 - key scoping" do
    test "different keys send independently and each creates its own record" do
      key_a = "em_scope_a_#{System.unique_integer()}"
      key_b = "em_scope_b_#{System.unique_integer()}"
      email = test_email()

      assert {:ok, _} =
               Messages.run_send_message_idempotent(email, email_attrs(key_a))

      assert_email_sent(subject: "Test Subject")

      assert {:ok, _} =
               Messages.run_send_message_idempotent(email, email_attrs(key_b))

      assert_email_sent(subject: "Test Subject")

      assert count_records_for_key(key_a) == 1
      assert count_records_for_key(key_b) == 1
    end

    test "same key with a different template is a separate send" do
      key = "em_tmpl_#{System.unique_integer()}"
      email = test_email()

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 email,
                 email_attrs(key, "booking_confirmation")
               )

      assert_email_sent(subject: "Test Subject")

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 email,
                 email_attrs(key, "event_notification")
               )

      assert_email_sent(subject: "Test Subject")

      # Two separate records because the template differs.
      assert count_records_for_key(key) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # run_send_sms_idempotent/3  (SMS)
  # ---------------------------------------------------------------------------

  describe "run_send_sms_idempotent/3 - first-time send" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "sends the SMS and creates exactly one idempotency record" do
      key = "sms_first_#{System.unique_integer()}"

      assert {:ok, %{id: message_id}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test SMS message.",
                 sms_attrs(key)
               )

      # In test / noop mode FlowRoute returns a fake mdr2-... ID.
      assert is_binary(message_id)
      assert String.starts_with?(message_id, "mdr2-")
      assert count_records_for_key(key) == 1
    end

    test "record contains the correct fields" do
      key = "sms_fields_#{System.unique_integer()}"
      template = "booking_checkin_reminder"

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 sms_attrs(key, template)
               )

      record = Ysc.Repo.get_by(MessageIdempotency, idempotency_key: key)
      assert record.message_type == :sms
      assert record.message_template == template
      assert record.phone_number == "12065551234"
    end
  end

  describe "run_send_sms_idempotent/3 - duplicate handling" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "duplicate SMS pre-check emits :sent telemetry with duplicate: true" do
      key = "sms_dup_telemetry_#{System.unique_integer()}"
      attrs = sms_attrs(key)
      body = "[YSC] Dup telemetry."
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-sms-dup-#{key}",
          [:ysc, :sms, :sent],
          fn _event, _measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:sms_sent_dup_flag, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:ok, _} =
               Messages.run_send_sms_idempotent("12065551234", body, attrs)

      assert {:ok, _} =
               Messages.run_send_sms_idempotent("12065551234", body, attrs)

      assert_receive {:sms_sent_dup_flag, first_meta}, 3_000
      refute first_meta[:duplicate] == true

      assert_receive {:sms_sent_dup_flag, second_meta}, 3_000
      assert second_meta[:duplicate] == true
    end

    test "second call with the same key returns {:ok, %{id: _}} without re-sending" do
      key = "sms_dup_#{System.unique_integer()}"
      attrs = sms_attrs(key)

      # First send – real (noop) ID.
      assert {:ok, %{id: first_id}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 attrs
               )

      assert String.starts_with?(first_id, "mdr2-")

      # Second send – pre-check fires; sentinel ID returned.
      assert {:ok, %{id: "mdr2-idempotent"}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 attrs
               )
    end

    test "exactly one record exists after any number of duplicate calls" do
      key = "sms_one_rec_#{System.unique_integer()}"
      attrs = sms_attrs(key)

      for _ <- 1..4 do
        assert {:ok, _} =
                 Messages.run_send_sms_idempotent(
                   "12065551234",
                   "[YSC] Test.",
                   attrs
                 )
      end

      assert count_records_for_key(key) == 1
    end

    test "both first and duplicate calls return {:ok, %{id: _}}" do
      key = "sms_ret_#{System.unique_integer()}"
      attrs = sms_attrs(key)

      {:ok, first} =
        Messages.run_send_sms_idempotent("12065551234", "[YSC] Test.", attrs)

      {:ok, second} =
        Messages.run_send_sms_idempotent("12065551234", "[YSC] Test.", attrs)

      assert is_binary(first.id)
      assert is_binary(second.id)
    end
  end

  describe "run_send_sms_idempotent/3 - key scoping" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "different keys send independently and each creates its own record" do
      key_a = "sms_scope_a_#{System.unique_integer()}"
      key_b = "sms_scope_b_#{System.unique_integer()}"

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] A.",
                 sms_attrs(key_a)
               )

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] B.",
                 sms_attrs(key_b)
               )

      assert count_records_for_key(key_a) == 1
      assert count_records_for_key(key_b) == 1
    end

    test "same key with a different template is a separate send" do
      key = "sms_tmpl_#{System.unique_integer()}"

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] A.",
                 sms_attrs(key, "booking_checkin_reminder")
               )

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] B.",
                 sms_attrs(key, "phone_verification")
               )

      assert count_records_for_key(key) == 2
    end

    test "accepts 10-digit national number (normalized to +1…) for send path" do
      key = "sms_10nat_#{System.unique_integer()}"

      # Use a number distinct from 12065551234 used elsewhere so rate-limit state does not collide.
      ten_digit =
        "425555#{rem(System.unique_integer([:positive]), 10_000) |> Integer.to_string() |> String.pad_leading(4, "0")}"

      assert {:ok, %{id: id}} =
               Messages.run_send_sms_idempotent(
                 ten_digit,
                 "[YSC] Ten-digit national.",
                 sms_attrs(key)
               )

      assert is_binary(id)
    end

    test "passes custom from number to Flowroute when provided" do
      key = "sms_from_#{System.unique_integer()}"

      attrs =
        sms_attrs(key)
        |> Map.put(:from, "12069876543")

      assert {:ok, %{id: id}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] From override.",
                 attrs
               )

      assert is_binary(id)
    end

    test "returns error when SMS body is empty (FlowRoute client rejects)" do
      key = "sms_empty_body_#{System.unique_integer()}"

      assert {:error, "failed to send SMS"} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "",
                 sms_attrs(key)
               )

      assert count_records_for_key(key) == 0
    end

    test "returns error and rolls back idempotency when from number is invalid" do
      key = "sms_bad_from_#{System.unique_integer()}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-sms-bad-from-#{key}",
          [:ysc, :sms, :send_failed],
          fn _event, measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:sms_send_failed_bad_from, measurements, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      attrs =
        sms_attrs(key)
        |> Map.put(:from, "not-a-valid-phone")

      assert {:error, "failed to send SMS"} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Bad from override.",
                 attrs
               )

      assert count_records_for_key(key) == 0

      assert_receive {:sms_send_failed_bad_from, %{count: 1}, meta}, 3_000
      assert meta.template == "booking_checkin_reminder"
      assert meta.idempotency_key == key
    end
  end

  describe "run_send_sms_idempotent/3 - rate limiting" do
    @tag async: false
    test "returns error when per-minute SMS rate limit is exceeded" do
      # Use a highly unique NANP-style number to avoid collisions with parallel tests.
      phone =
        ("1" <>
           String.pad_leading(
             Integer.to_string(System.unique_integer([:positive])),
             10,
             "0"
           ))
        |> String.slice(0, 11)

      # Pre-populate the rate limit cache directly instead of going through
      # 5 real sends. This keeps the window between "cache is full" and the
      # 6th-send assertion essentially zero, preventing flakiness caused by
      # concurrent async tests calling Cachex.clear(:ysc_cache).
      for _ <- 1..5, do: SmsRateLimit.record_sms_send(phone)

      key6 = "sms_rl_blocked_#{System.unique_integer()}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-sms-rl-exceeded-#{key6}",
          [:ysc, :sms, :rate_limit_exceeded],
          fn _event, measurements, metadata, _ ->
            if metadata[:idempotency_key] == key6 do
              send(parent, {:sms_rl_exceeded, measurements, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:error, msg} =
               Messages.run_send_sms_idempotent(
                 phone,
                 "[YSC] Should block.",
                 sms_attrs(key6)
               )

      assert is_binary(msg)

      assert_receive {:sms_rl_exceeded, %{count: 1}, meta}, 3_000
      assert meta.template == "booking_checkin_reminder"
      assert meta.recipient == phone
    end

    test "returns error for invalid phone before transaction (send_sms error path)" do
      key = "sms_bad_to_#{System.unique_integer()}"

      assert {:error, "failed to send SMS"} =
               Messages.run_send_sms_idempotent(
                 "not-a-valid-nanp-phone",
                 "[YSC] Body ok.",
                 sms_attrs(key)
               )

      assert count_records_for_key(key) == 0
    end
  end

  describe "run_send_sms_idempotent/3 — unique_user_phone/0" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "first successful send uses unique phone from AccountsFixtures" do
      phone = unique_user_phone()
      phone_digits = String.trim_leading(phone, "+")
      key = "sms_unique_phone_#{System.unique_integer()}"

      assert {:ok, %{id: message_id}} =
               Messages.run_send_sms_idempotent(
                 phone,
                 "[YSC] Unique phone SMS.",
                 sms_attrs_phone(key, phone_digits)
               )

      assert String.starts_with?(message_id, "mdr2-")
      assert count_records_for_key(key) == 1
    end

    test "successful send emits sms :sent telemetry with message_id (not duplicate)" do
      Cachex.clear(:ysc_cache)
      phone = unique_user_phone()
      phone_digits = String.trim_leading(phone, "+")
      key = "sms_tel_mid_#{System.unique_integer()}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-sms-msgid-#{key}",
          [:ysc, :sms, :sent],
          fn _event, _measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:sms_sent_with_msg_id, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:ok, %{id: mdr2_id}} =
               Messages.run_send_sms_idempotent(
                 phone,
                 "[YSC] Telemetry message id.",
                 sms_attrs_phone(key, phone_digits)
               )

      assert_receive {:sms_sent_with_msg_id, meta}, 3_000
      assert meta[:duplicate] != true
      assert meta[:message_id] == mdr2_id

      # Telemetry uses the same string passed to run_send_sms_idempotent/3 (E.164 from unique_user_phone/0).
      assert meta.recipient == phone
    end
  end

  describe "run_send_sms_idempotent/3 - concurrent idempotency" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "concurrent calls with the same key leave a single row", %{
      sandbox_owner: owner
    } do
      key = "sms_conc_#{System.unique_integer()}"
      attrs = sms_attrs(key)
      body = "[YSC] Concurrent."

      t1 =
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          Messages.run_send_sms_idempotent("12065551234", body, attrs)
        end)

      t2 =
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          Messages.run_send_sms_idempotent("12065551234", body, attrs)
        end)

      assert {:ok, _} = Task.await(t1)
      assert {:ok, _} = Task.await(t2)
      assert count_records_for_key(key) == 1
    end
  end

  describe "run_send_message_idempotent/2 - concurrent idempotency" do
    test "concurrent calls with the same key leave a single row", %{
      sandbox_owner: owner
    } do
      key = "em_conc_#{System.unique_integer()}"
      attrs = email_attrs(key)
      email = test_email()

      t1 =
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          Messages.run_send_message_idempotent(email, attrs)
        end)

      t2 =
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          Messages.run_send_message_idempotent(email, attrs)
        end)

      assert {:ok, _} = Task.await(t1)
      assert {:ok, _} = Task.await(t2)
      assert count_records_for_key(key) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-type isolation
  # ---------------------------------------------------------------------------

  describe "message_type isolation" do
    setup do
      Cachex.clear(:ysc_cache)
      :ok
    end

    test "email and SMS records with the same idempotency key do not conflict" do
      # The DB unique constraint is (message_type, idempotency_key, message_template).
      # Because message_type differs, both sends must succeed and each creates
      # its own record.
      key = "cross_type_#{System.unique_integer()}"
      email = test_email()

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 email,
                 email_attrs(key, "booking_confirmation")
               )

      assert_email_sent(subject: "Test Subject")

      assert {:ok, _} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 sms_attrs(key, "booking_checkin_reminder")
               )

      assert count_records_for_key(key) == 2
    end

    test "duplicate email send does not block an SMS with the same key" do
      key = "no_cross_block_#{System.unique_integer()}"
      email = test_email()

      # Send email twice with the same key – second send is deduplicated.
      assert {:ok, _} =
               Messages.run_send_message_idempotent(email, email_attrs(key))

      assert_email_sent(subject: "Test Subject")

      assert {:ok, _} =
               Messages.run_send_message_idempotent(email, email_attrs(key))

      assert_no_email_sent()

      # SMS with the same key should still go through (different message_type).
      assert {:ok, %{id: sms_id}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Test.",
                 sms_attrs(key, "booking_checkin_reminder")
               )

      assert String.starts_with?(sms_id, "mdr2-")
    end
  end

  # ---------------------------------------------------------------------------
  # create_message_idempotency/1  (schema / DB constraint tests)
  # ---------------------------------------------------------------------------

  describe "create_message_idempotency/1" do
    setup do
      %{user: user_fixture()}
    end

    test "creates a record with valid attrs", %{user: user} do
      attrs = %{
        user_id: user.id,
        idempotency_key: "schema_key_#{System.unique_integer()}",
        message_template: "test_template",
        message_type: :email
      }

      assert {:ok, %MessageIdempotency{} = record} =
               Messages.create_message_idempotency(attrs)

      assert record.user_id == user.id
      assert record.idempotency_key == attrs.idempotency_key
    end

    test "rejects a duplicate (type, key, template) triplet", %{user: user} do
      key = "schema_dup_#{System.unique_integer()}"

      attrs = %{
        user_id: user.id,
        idempotency_key: key,
        message_template: "test_template",
        message_type: :email
      }

      assert {:ok, _} = Messages.create_message_idempotency(attrs)
      assert {:error, changeset} = Messages.create_message_idempotency(attrs)
      # The changeset error is placed on :message_type (the first field in
      # the unique_constraint declaration).
      assert changeset.errors[:message_type] != nil
    end

    test "allows same key with different message_type", %{user: user} do
      key = "schema_type_#{System.unique_integer()}"

      email_attrs_rec = %{
        user_id: user.id,
        idempotency_key: key,
        message_template: "test_template",
        message_type: :email
      }

      sms_attrs_rec = %{email_attrs_rec | message_type: :sms}

      assert {:ok, _} = Messages.create_message_idempotency(email_attrs_rec)
      assert {:ok, _} = Messages.create_message_idempotency(sms_attrs_rec)
    end

    test "allows same key with different template", %{user: user} do
      key = "schema_tmpl_#{System.unique_integer()}"

      attrs_a = %{
        user_id: user.id,
        idempotency_key: key,
        message_template: "template_a",
        message_type: :email
      }

      attrs_b = %{attrs_a | message_template: "template_b"}

      assert {:ok, _} = Messages.create_message_idempotency(attrs_a)
      assert {:ok, _} = Messages.create_message_idempotency(attrs_b)
    end

    test "requires idempotency_key" do
      assert {:error, %Ecto.Changeset{errors: errors}} =
               Messages.create_message_idempotency(%{
                 message_template: "tmpl",
                 message_type: :email
               })

      assert Keyword.has_key?(errors, :idempotency_key)
    end

    test "requires message_template" do
      assert {:error, %Ecto.Changeset{errors: errors}} =
               Messages.create_message_idempotency(%{
                 idempotency_key: "k",
                 message_type: :email
               })

      assert Keyword.has_key?(errors, :message_template)
    end

    test "requires message_type" do
      assert {:error, %Ecto.Changeset{errors: errors}} =
               Messages.create_message_idempotency(%{
                 idempotency_key: "k",
                 message_template: "tmpl"
               })

      assert Keyword.has_key?(errors, :message_type)
    end
  end

  # ---------------------------------------------------------------------------
  # list_user_messages/2  and  count_user_messages/1
  # ---------------------------------------------------------------------------

  describe "list_user_messages/2" do
    setup do
      %{user: user_fixture()}
    end

    test "returns empty list when user has no matching rows", %{
      user: user
    } do
      assert Messages.list_user_messages(user.id) == []
    end

    test "includes rows matched by email when email option is set", %{
      user: query_user
    } do
      owner = user_fixture()
      shared_email = "shared_lookup_#{System.unique_integer()}@example.com"

      {:ok, _} =
        Messages.create_message_idempotency(%{
          user_id: owner.id,
          email: shared_email,
          idempotency_key: "lum_email_k_#{System.unique_integer()}",
          message_template: "tmpl",
          message_type: :email
        })

      rows =
        Messages.list_user_messages(query_user.id,
          email: shared_email,
          limit: 50
        )

      assert Enum.any?(rows, &(&1.email == shared_email))
    end

    test "returns messages for a user", %{user: user} do
      insert_record(user.id, "lum_k1_#{System.unique_integer()}", "t1")
      insert_record(user.id, "lum_k2_#{System.unique_integer()}", "t2")

      messages = Messages.list_user_messages(user.id)
      assert length(messages) >= 2
    end

    test "respects limit option", %{user: user} do
      for i <- 1..5 do
        insert_record(
          user.id,
          "lum_lim_#{i}_#{System.unique_integer()}",
          "tmpl"
        )
      end

      assert length(Messages.list_user_messages(user.id, limit: 2)) == 2
    end

    test "respects offset option", %{user: user} do
      for i <- 1..5 do
        insert_record(
          user.id,
          "lum_off_#{i}_#{System.unique_integer()}",
          "tmpl"
        )
      end

      all = Messages.list_user_messages(user.id)
      offset = Messages.list_user_messages(user.id, offset: 2)
      assert length(offset) == length(all) - 2
    end

    test "when email option is not a binary, filters by user_id only", %{
      user: user
    } do
      insert_record(user.id, "lum_atom_#{System.unique_integer()}", "tmpl")

      rows =
        Messages.list_user_messages(user.id, email: :not_a_binary, limit: 50)

      assert rows != []
      assert Enum.all?(rows, &(&1.user_id == user.id))
    end

    test "offset beyond total returns empty list", %{user: user} do
      insert_record(user.id, "lum_off_end_#{System.unique_integer()}", "tmpl")

      assert Messages.list_user_messages(user.id, offset: 9_999, limit: 10) ==
               []
    end
  end

  describe "count_user_messages/1" do
    setup do
      %{user: user_fixture()}
    end

    test "returns the correct count", %{user: user} do
      insert_record(user.id, "cum_k1_#{System.unique_integer()}", "t1")
      insert_record(user.id, "cum_k2_#{System.unique_integer()}", "t2")

      assert Messages.count_user_messages(user.id) >= 2
    end

    test "returns 0 when user has no messages", %{user: user} do
      assert Messages.count_user_messages(user.id) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp insert_record(user_id, key, template) do
    {:ok, record} =
      Messages.create_message_idempotency(%{
        user_id: user_id,
        idempotency_key: key,
        message_template: template,
        message_type: :email
      })

    record
  end
end

defmodule Ysc.MessagesTest.MailerDeliverFailure do
  @moduledoc """
  Serial tests that swap `Ysc.Mailer` adapter — must run with `async: false`.

  Kept in this file so `mix test test/ysc/messages_test.exs` exercises
  `handle_mailer_deliver_error/3` and related transaction error paths.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Messages

  setup do
    prev = Application.get_env(:ysc, Ysc.Mailer) || []
    on_exit(fn -> Application.put_env(:ysc, Ysc.Mailer, prev) end)
    {:ok, mailer_config: prev}
  end

  describe "run_send_message_idempotent/2 when Mailer.deliver fails" do
    test "returns error and does not persist idempotency row (transaction rolls back)",
         %{
           mailer_config: mailer_config
         } do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config, adapter: Ysc.Test.FailingSwooshAdapter)
      )

      key = "em_fail_#{System.unique_integer()}"

      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-email-adapter-send-failed-#{key}",
          [:ysc, :email, :send_failed],
          fn _event, measurements, metadata, _ ->
            send(parent, {:email_send_failed_telemetry, measurements, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:error, "failed to send email"} =
               Messages.run_send_message_idempotent(
                 Swoosh.Email.new()
                 |> Swoosh.Email.to("fail-recipient@example.com")
                 |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
                 |> Swoosh.Email.subject("Fail")
                 |> Swoosh.Email.text_body("x"),
                 %{
                   message_type: :email,
                   idempotency_key: key,
                   message_template: "booking_confirmation",
                   params: %{},
                   email: "fail-recipient@example.com",
                   rendered_message: "<p>x</p>"
                 }
               )

      assert_receive {:email_send_failed_telemetry, %{count: 1}, meta}, 3_000
      assert meta.recipient == "fail-recipient@example.com"
      assert meta.template == "booking_confirmation"

      assert Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: key
             ) == nil
    end

    test "send_failed telemetry uses inspect fallback for non-standard recipient",
         %{
           mailer_config: mailer_config
         } do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config, adapter: Ysc.Test.FailingSwooshAdapter)
      )

      key = "em_fail_inspect_#{System.unique_integer()}"

      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-email-adapter-inspect-#{key}",
          [:ysc, :email, :send_failed],
          fn _event, measurements, metadata, _ ->
            send(parent, {:email_send_failed_inspect, measurements, metadata})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:error, "failed to send email"} =
               Messages.run_send_message_idempotent(
                 Swoosh.Email.new()
                 |> Map.put(:to, %{not_a: "valid_recipient"})
                 |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
                 |> Swoosh.Email.subject("Fail")
                 |> Swoosh.Email.text_body("x"),
                 %{
                   message_type: :email,
                   idempotency_key: key,
                   message_template: "booking_confirmation",
                   params: %{},
                   email: "fail-recipient@example.com",
                   rendered_message: "<p>x</p>"
                 }
               )

      assert_receive {:email_send_failed_inspect, %{count: 1}, meta}, 3_000
      assert meta.recipient =~ "%{not_a: \"valid_recipient\"}"
    end

    test "send_failed telemetry uses binary recipient string from email_recipient_to_string/1",
         %{
           mailer_config: mailer_config
         } do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config, adapter: Ysc.Test.FailingSwooshAdapter)
      )

      key = "em_fail_binary_to_#{System.unique_integer()}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-email-binary-to-#{key}",
          [:ysc, :email, :send_failed],
          fn _event, measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(
                parent,
                {:email_send_failed_binary_to, measurements, metadata}
              )
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:error, "failed to send email"} =
               Messages.run_send_message_idempotent(
                 Swoosh.Email.new()
                 |> Swoosh.Email.to("binary-recipient-fail@example.com")
                 |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
                 |> Swoosh.Email.subject("Fail")
                 |> Swoosh.Email.text_body("x"),
                 %{
                   message_type: :email,
                   idempotency_key: key,
                   message_template: "booking_confirmation",
                   params: %{},
                   email: "binary-recipient-fail@example.com",
                   rendered_message: "<p>x</p>"
                 }
               )

      assert_receive {:email_send_failed_binary_to, %{count: 1}, meta}, 3_000
      assert meta.recipient == "binary-recipient-fail@example.com"
    end
  end
end

defmodule Ysc.MessagesTest.EmailDeliveryRescueAndSesEdgeCases do
  @moduledoc """
  Covers `Ysc.Messages` rescue paths in `run_send_message_idempotent/2` and SES
  tag building when optional attrs are nil (`async: false`).
  """
  use Ysc.DataCase, async: false

  alias Ysc.Messages

  setup do
    prev = Application.get_env(:ysc, Ysc.Mailer) || []
    on_exit(fn -> Application.put_env(:ysc, Ysc.Mailer, prev) end)

    on_exit(fn ->
      Application.delete_env(:ysc, :test_constraint_error_name)
      Application.delete_env(:ysc, :test_constraint_error_type)
    end)

    {:ok, mailer_config: prev}
  end

  describe "run_send_message_idempotent/2 — SES tags omit user_id when nil" do
    test "maybe_put_ses_tag skips user_id when user_id is nil" do
      prev_ses = Application.get_env(:ysc, :ses_configuration_set)

      Application.put_env(:ysc, :ses_configuration_set, "test-ses-config-set")

      on_exit(fn ->
        if prev_ses == nil do
          Application.delete_env(:ysc, :ses_configuration_set)
        else
          Application.put_env(:ysc, :ses_configuration_set, prev_ses)
        end
      end)

      key = "em_no_uid_" <> Ecto.UUID.generate()

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 Swoosh.Email.new()
                 |> Swoosh.Email.to("no-uid@example.com")
                 |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
                 |> Swoosh.Email.subject("No uid")
                 |> Swoosh.Email.html_body("<p>x</p>"),
                 %{
                   message_type: :email,
                   idempotency_key: key,
                   message_template: "booking_confirmation",
                   params: %{},
                   email: "no-uid@example.com",
                   rendered_message: "<p>x</p>",
                   user_id: nil,
                   edition_id: "01HM1234567890ABCDEFGH",
                   subscriber_id: "01HM9876543210ZYXWVUTS"
                 }
               )

      assert_receive {:email, delivered}, 3_000
      tags = delivered.provider_options[:tags] || []

      refute Enum.any?(tags, &(&1[:name] == "user_id"))

      assert Enum.any?(
               tags,
               &(&1[:name] == "edition_id" and
                   &1[:value] == "01HM1234567890ABCDEFGH")
             )
    end
  end

  describe "run_send_message_idempotent/2 — duplicate insert via concurrent calls" do
    test "second transaction sees idempotency duplicate and returns {:ok, email}",
         %{sandbox_owner: owner} do
      key =
        "em_dup_txn_" <> Integer.to_string(System.unique_integer([:positive]))

      attrs = %{
        message_type: :email,
        idempotency_key: key,
        message_template: "booking_confirmation",
        params: %{},
        email: "dup-txn@example.com",
        rendered_message: "<p>x</p>"
      }

      email =
        Swoosh.Email.new()
        |> Swoosh.Email.to("dup-txn@example.com")
        |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
        |> Swoosh.Email.subject("Dup txn")
        |> Swoosh.Email.html_body("<p>x</p>")

      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-dup-txn-#{key}",
          [:ysc, :email, :sent],
          fn _event, _measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:dup_txn_sent, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      t1 =
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          Messages.run_send_message_idempotent(email, attrs)
        end)

      t2 =
        Task.async(fn ->
          Ysc.DataCase.allow_sandbox(self(), owner)
          Messages.run_send_message_idempotent(email, attrs)
        end)

      assert {:ok, _} = Task.await(t1)
      assert {:ok, _} = Task.await(t2)

      metas = flush_dup_txn_sent([])

      assert match?([_, _ | _], metas)
      assert Enum.any?(metas, &(&1[:duplicate] == true))
    end

    defp flush_dup_txn_sent(acc) do
      receive do
        {:dup_txn_sent, m} -> flush_dup_txn_sent([m | acc])
      after
        50 -> Enum.reverse(acc)
      end
    end
  end

  describe "run_send_message_idempotent/2 — Mailer raises Ecto.ConstraintError (idempotency unique)" do
    test "treats idempotency unique constraint as success", %{
      mailer_config: mailer_config
    } do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config,
          adapter: Ysc.Test.SwooshAdapterRaisesConstraintError
        )
      )

      Application.put_env(
        :ysc,
        :test_constraint_error_name,
        "message_idempotency_entries_unique_index"
      )

      Application.put_env(:ysc, :test_constraint_error_type, :unique)

      key =
        "em_constr_idem_" <>
          Integer.to_string(System.unique_integer([:positive]))

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 Swoosh.Email.new()
                 |> Swoosh.Email.to("constr-idem@example.com")
                 |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
                 |> Swoosh.Email.subject("C")
                 |> Swoosh.Email.text_body("x"),
                 %{
                   message_type: :email,
                   idempotency_key: key,
                   message_template: "booking_confirmation",
                   params: %{},
                   email: "constr-idem@example.com",
                   rendered_message: "<p>x</p>"
                 }
               )

      assert Ysc.Repo.get_by(Ysc.Messages.MessageIdempotency,
               idempotency_key: key
             ) ==
               nil
    end

    test "non-idempotency unique constraint returns error", %{
      mailer_config: mailer_config
    } do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config,
          adapter: Ysc.Test.SwooshAdapterRaisesConstraintError
        )
      )

      Application.put_env(
        :ysc,
        :test_constraint_error_name,
        "some_other_unique_ix"
      )

      Application.put_env(:ysc, :test_constraint_error_type, :unique)

      key =
        "em_constr_other_" <>
          Integer.to_string(System.unique_integer([:positive]))

      assert {:error, "failed to send email"} =
               Messages.run_send_message_idempotent(
                 Swoosh.Email.new()
                 |> Swoosh.Email.to("constr-other@example.com")
                 |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
                 |> Swoosh.Email.subject("C")
                 |> Swoosh.Email.text_body("x"),
                 %{
                   message_type: :email,
                   idempotency_key: key,
                   message_template: "booking_confirmation",
                   params: %{},
                   email: "constr-other@example.com",
                   rendered_message: "<p>x</p>"
                 }
               )
    end

    test "non-unique constraint returns error", %{mailer_config: mailer_config} do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config,
          adapter: Ysc.Test.SwooshAdapterRaisesConstraintError
        )
      )

      Application.put_env(:ysc, :test_constraint_error_name, "bookings_fkey")
      Application.put_env(:ysc, :test_constraint_error_type, :foreign_key)

      key =
        "em_constr_fk_" <> Integer.to_string(System.unique_integer([:positive]))

      assert {:error, "failed to send email"} =
               Messages.run_send_message_idempotent(
                 Swoosh.Email.new()
                 |> Swoosh.Email.to("constr-fk@example.com")
                 |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
                 |> Swoosh.Email.subject("C")
                 |> Swoosh.Email.text_body("x"),
                 %{
                   message_type: :email,
                   idempotency_key: key,
                   message_template: "booking_confirmation",
                   params: %{},
                   email: "constr-fk@example.com",
                   rendered_message: "<p>x</p>"
                 }
               )
    end

    test "idempotency unique constraint alternate index name is treated as success",
         %{
           mailer_config: mailer_config
         } do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config,
          adapter: Ysc.Test.SwooshAdapterRaisesConstraintError
        )
      )

      Application.put_env(
        :ysc,
        :test_constraint_error_name,
        "message_idempotency_entries_message_type_idempotency_key_messag"
      )

      Application.put_env(:ysc, :test_constraint_error_type, :unique)

      key =
        "em_constr_alt_" <>
          Integer.to_string(System.unique_integer([:positive]))

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 Swoosh.Email.new()
                 |> Swoosh.Email.to("constr-alt@example.com")
                 |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
                 |> Swoosh.Email.subject("C")
                 |> Swoosh.Email.text_body("x"),
                 %{
                   message_type: :email,
                   idempotency_key: key,
                   message_template: "booking_confirmation",
                   params: %{},
                   email: "constr-alt@example.com",
                   rendered_message: "<p>x</p>"
                 }
               )
    end

    test "non-ConstraintError from Mailer is caught and emits send_failed telemetry",
         %{
           mailer_config: mailer_config
         } do
      Application.put_env(
        :ysc,
        Ysc.Mailer,
        Keyword.merge(mailer_config,
          adapter: Ysc.Test.SwooshAdapterRaisesRuntimeError
        )
      )

      key =
        "em_runtime_" <> Integer.to_string(System.unique_integer([:positive]))

      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-email-runtime-#{key}",
          [:ysc, :email, :send_failed],
          fn _event, measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:email_send_failed_runtime, measurements, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:error, "failed to send email"} =
               Messages.run_send_message_idempotent(
                 Swoosh.Email.new()
                 |> Swoosh.Email.to("runtime-fail@example.com")
                 |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
                 |> Swoosh.Email.subject("R")
                 |> Swoosh.Email.text_body("x"),
                 %{
                   message_type: :email,
                   idempotency_key: key,
                   message_template: "booking_confirmation",
                   params: %{},
                   email: "runtime-fail@example.com",
                   rendered_message: "<p>x</p>"
                 }
               )

      assert_receive {:email_send_failed_runtime, %{count: 1}, meta}, 3_000
      assert meta.template == "booking_confirmation"
      assert meta.recipient == "runtime-fail@example.com"
    end
  end
end

defmodule Ysc.MessagesTest.FlowrouteTestRaise do
  @moduledoc false
  use Ysc.DataCase, async: false

  alias Ysc.Messages

  setup do
    Cachex.clear(:ysc_cache)
    on_exit(fn -> Application.delete_env(:ysc, :flowroute_test_raise) end)
    :ok
  end

  describe "run_send_sms_idempotent/3 with :flowroute_test_raise" do
    test "runtime exception emits sms :send_failed telemetry" do
      Application.put_env(:ysc, :flowroute_test_raise, {:runtime, "sms boom"})

      key = "sms_raise_rt_#{System.unique_integer([:positive])}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-sms-rt-#{key}",
          [:ysc, :sms, :send_failed],
          fn _event, measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:sms_failed_rt, measurements, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:error, "failed to send SMS"} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Body.",
                 %{
                   message_type: :sms,
                   idempotency_key: key,
                   message_template: "booking_checkin_reminder",
                   params: %{},
                   phone_number: "12065551234",
                   rendered_message: "[YSC] Body."
                 }
               )

      assert_receive {:sms_failed_rt, %{count: 1}, meta}, 3_000
      assert meta.template == "booking_checkin_reminder"
    end

    test "idempotency unique constraint from FlowRoute treats as success" do
      Application.put_env(
        :ysc,
        :flowroute_test_raise,
        {:constraint, "message_idempotency_entries_unique_index", :unique}
      )

      key = "sms_raise_idem_#{System.unique_integer([:positive])}"

      assert {:ok, %{id: "mdr2-idempotent"}} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Body.",
                 %{
                   message_type: :sms,
                   idempotency_key: key,
                   message_template: "booking_checkin_reminder",
                   params: %{},
                   phone_number: "12065551234",
                   rendered_message: "[YSC] Body."
                 }
               )
    end

    test "non-idempotency unique constraint returns error and telemetry" do
      Application.put_env(
        :ysc,
        :flowroute_test_raise,
        {:constraint, "some_other_unique_constraint", :unique}
      )

      key = "sms_raise_other_#{System.unique_integer([:positive])}"
      parent = self()

      ref =
        :telemetry.attach(
          "ysc-messages-sms-uc-#{key}",
          [:ysc, :sms, :send_failed],
          fn _event, measurements, metadata, _ ->
            if metadata[:idempotency_key] == key do
              send(parent, {:sms_failed_uc, measurements, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(ref) end)

      assert {:error, "failed to send SMS"} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Body.",
                 %{
                   message_type: :sms,
                   idempotency_key: key,
                   message_template: "phone_verification",
                   params: %{},
                   phone_number: "12065551234",
                   rendered_message: "[YSC] Body."
                 }
               )

      assert_receive {:sms_failed_uc, %{count: 1}, _meta}, 3_000
    end

    test "non-unique constraint error returns error" do
      Application.put_env(
        :ysc,
        :flowroute_test_raise,
        {:constraint, "bookings_fkey", :foreign_key}
      )

      key = "sms_raise_fk_#{System.unique_integer([:positive])}"

      assert {:error, "failed to send SMS"} =
               Messages.run_send_sms_idempotent(
                 "12065551234",
                 "[YSC] Body.",
                 %{
                   message_type: :sms,
                   idempotency_key: key,
                   message_template: "booking_checkin_reminder",
                   params: %{},
                   phone_number: "12065551234",
                   rendered_message: "[YSC] Body."
                 }
               )
    end
  end
end
