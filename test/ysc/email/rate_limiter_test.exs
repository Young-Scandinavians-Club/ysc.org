defmodule Ysc.Email.RateLimiterTest do
  @moduledoc """
  Tests for the PostgreSQL-backed SES send rate limiter introduced in #858.

  The limiter is shared across application nodes and gates every durable email
  delivery path through `Ysc.Messages.run_send_message_idempotent/2`.
  """
  use Ysc.DataCase, async: false

  alias Ysc.Email.RateLimiter
  alias Ysc.Repo

  setup do
    original_rate = Application.get_env(:ysc, :ses_max_send_rate)
    original_window = Application.get_env(:ysc, :ses_rate_window_seconds)
    original_region = Application.get_env(:ysc, :ses_region)

    test_region = "test-#{System.unique_integer([:positive])}"
    Application.put_env(:ysc, :ses_region, test_region)
    Application.put_env(:ysc, :ses_max_send_rate, 3)
    Application.put_env(:ysc, :ses_rate_window_seconds, 60)

    key = "ses:#{test_region}"
    Repo.query!("DELETE FROM email_rate_limits WHERE key = $1", [key])

    on_exit(fn ->
      Application.put_env(:ysc, :ses_max_send_rate, original_rate)
      Application.put_env(:ysc, :ses_rate_window_seconds, original_window)
      Application.put_env(:ysc, :ses_region, original_region)
      Repo.query!("DELETE FROM email_rate_limits WHERE key = $1", [key])
    end)

    {:ok, key: key}
  end

  describe "check/1" do
    test "allows sends under the configured max rate" do
      assert :ok = RateLimiter.check()
      assert :ok = RateLimiter.check()
      assert :ok = RateLimiter.check()
    end

    test "returns rate_limited when max rate is exceeded within the window" do
      assert :ok = RateLimiter.check()
      assert :ok = RateLimiter.check()
      assert :ok = RateLimiter.check()

      assert {:error, :rate_limited, retry_after} = RateLimiter.check()
      assert is_integer(retry_after)
      assert retry_after > 0
      assert retry_after <= 60
    end

    test "counts multiple destinations in a single check" do
      assert :ok = RateLimiter.check(2)

      assert {:error, :rate_limited, _} = RateLimiter.check(2)
    end

    test "allows sends again after the rate window expires", %{key: key} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("email_rate_limits", [
        %{
          key: key,
          window_started_at: DateTime.add(now, -120, :second),
          used: 3,
          updated_at: now
        }
      ])

      assert :ok = RateLimiter.check()
    end

    test "increments used count within an active window", %{key: key} do
      assert :ok = RateLimiter.check()
      assert :ok = RateLimiter.check()

      row =
        Repo.one!(
          from(r in "email_rate_limits",
            where: r.key == ^key,
            select: %{used: r.used, window_started_at: r.window_started_at}
          )
        )

      assert row.used == 2
      assert row.window_started_at != nil
    end
  end

  describe "throttle!/1" do
    test "blocks checks until cooldown expires", %{key: key} do
      assert :ok = RateLimiter.throttle!(30)

      assert {:error, :rate_limited, retry_after} = RateLimiter.check()
      assert retry_after > 0
      assert retry_after <= 30

      row =
        Repo.one!(
          from(r in "email_rate_limits",
            where: r.key == ^key,
            select: %{cooldown_until: r.cooldown_until}
          )
        )

      assert row.cooldown_until != nil
    end

    test "upserts cooldown on an existing rate-limit row", %{key: key} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("email_rate_limits", [
        %{
          key: key,
          window_started_at: now,
          used: 2,
          updated_at: now
        }
      ])

      assert :ok = RateLimiter.throttle!(45)

      assert {:error, :rate_limited, retry_after} = RateLimiter.check()
      assert retry_after > 0
      assert retry_after <= 45
    end
  end

  describe "integration with Messages.run_send_message_idempotent/2" do
    import Swoosh.TestAssertions

    alias Ysc.Messages

    defp durable_email_attrs(key) do
      %{
        message_type: :email,
        idempotency_key: key,
        message_template: "booking_confirmation",
        params: %{},
        email: "rate-limit@example.com",
        rendered_message: "<p>Test body</p>",
        delivery_retry: true
      }
    end

    defp durable_test_email(opts \\ []) do
      recipient = Keyword.get(opts, :to, "rate-limit@example.com")

      Swoosh.Email.new()
      |> Swoosh.Email.to(recipient)
      |> Swoosh.Email.from({"YSC Test", "noreply@ysc.org"})
      |> Swoosh.Email.subject("Rate limit test")
      |> Swoosh.Email.html_body("<p>Test body</p>")
      |> Swoosh.Email.text_body("Test body")
    end

    test "returns {:error, {:snooze, seconds}} when SES rate limit is exceeded" do
      Application.put_env(:ysc, :ses_max_send_rate, 1)

      key1 = "rate_snooze_1_#{System.unique_integer()}"
      key2 = "rate_snooze_2_#{System.unique_integer()}"

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 durable_test_email(),
                 durable_email_attrs(key1)
               )

      assert_email_sent()

      assert {:error, {:snooze, retry_after}} =
               Messages.run_send_message_idempotent(
                 durable_test_email(to: "other-#{key2}@example.com"),
                 durable_email_attrs(key2)
               )

      assert is_integer(retry_after)
      assert retry_after > 0
    end

    test "counts cc recipients toward the SES send quota" do
      Application.put_env(:ysc, :ses_max_send_rate, 2)

      key1 = "rate_cc_1_#{System.unique_integer()}"
      key2 = "rate_cc_2_#{System.unique_integer()}"

      assert {:ok, _} =
               Messages.run_send_message_idempotent(
                 durable_test_email(),
                 durable_email_attrs(key1)
               )

      email_with_cc =
        durable_test_email(to: "cc-test@example.com")
        |> Swoosh.Email.cc("cc@example.com")

      assert {:error, {:snooze, _}} =
               Messages.run_send_message_idempotent(
                 email_with_cc,
                 durable_email_attrs(key2)
               )

      assert %Ysc.Messages.MessageIdempotency{delivery_status: :pending} =
               Repo.get_by(Ysc.Messages.MessageIdempotency,
                 idempotency_key: key2
               )
    end
  end
end
