defmodule Ysc.EmailVerificationRateLimitTest do
  use ExUnit.Case, async: false

  alias Ysc.EmailVerificationRateLimit

  setup do
    user_id = Ecto.ULID.generate()
    on_exit(fn -> :ok end)
    {:ok, user_id: user_id}
  end

  describe "check/2" do
    test "allows verification attempts under the limit", %{user_id: user_id} do
      assert :ok = EmailVerificationRateLimit.check(user_id, :email)
      assert :ok = EmailVerificationRateLimit.check(user_id, :phone)
    end

    test "rate limits after exceeding the per-minute attempt limit", %{user_id: user_id} do
      limit =
        Application.get_env(:ysc, EmailVerificationRateLimit, [])[
          :attempt_limit_per_minute
        ] || 12

      for _ <- 1..limit do
        assert :ok = EmailVerificationRateLimit.check(user_id, :email)
      end

      assert :rate_limited = EmailVerificationRateLimit.check(user_id, :email)
    end

    test "scopes email and phone limits independently", %{user_id: user_id} do
      limit =
        Application.get_env(:ysc, EmailVerificationRateLimit, [])[
          :attempt_limit_per_minute
        ] || 12

      for _ <- 1..limit do
        assert :ok = EmailVerificationRateLimit.check(user_id, :email)
      end

      assert :rate_limited = EmailVerificationRateLimit.check(user_id, :email)
      assert :ok = EmailVerificationRateLimit.check(user_id, :phone)
    end

    test "rejects invalid arguments", %{user_id: user_id} do
      assert :rate_limited = EmailVerificationRateLimit.check(user_id, :invalid)
      assert :rate_limited = EmailVerificationRateLimit.check(nil, :email)
    end
  end
end
