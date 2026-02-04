defmodule Ysc.ResendRateLimiterTest do
  use ExUnit.Case, async: true

  alias Ysc.ResendRateLimiter

  setup do
    # Best-effort cleanup; cache may not be started in some envs.
    Cachex.del(:ysc_cache, "resend_email:1")
    Cachex.del(:ysc_cache, "resend_sms:1")
    :ok
  end

  describe "resend_allowed?/3 and record_resend/3" do
    test "allows when no cache entry exists" do
      assert {:ok, :allowed} = ResendRateLimiter.resend_allowed?(1, :email, 60)
      assert ResendRateLimiter.remaining_seconds(1, :email, 60) == 0
    end

    test "rate limits after record_resend/3" do
      assert :ok = ResendRateLimiter.record_resend(1, :email, 60)

      assert {:error, :rate_limited, remaining} =
               ResendRateLimiter.resend_allowed?(1, :email, 60)

      assert is_integer(remaining)
      assert remaining > 0
    end

    test "check_and_record_resend/3 records when allowed" do
      assert {:ok, :allowed} =
               ResendRateLimiter.check_and_record_resend(1, :sms, 60)

      assert {:error, :rate_limited, _} =
               ResendRateLimiter.check_and_record_resend(1, :sms, 60)
    end
  end

  describe "disabled_until/1" do
    test "returns a DateTime in the future" do
      dt = ResendRateLimiter.disabled_until(10)
      assert DateTime.compare(dt, DateTime.utc_now()) == :gt
    end
  end

  describe "LiveView helpers" do
    test "resend_available?/2 true when missing assigns" do
      assert ResendRateLimiter.resend_available?(%{}, :email)
      assert ResendRateLimiter.resend_available?(%{}, :sms)
    end

    test "resend_available?/2 false when disabled_until is in future" do
      future = DateTime.add(DateTime.utc_now(), 30, :second)

      refute ResendRateLimiter.resend_available?(
               %{email_resend_disabled_until: future},
               :email
             )

      refute ResendRateLimiter.resend_available?(
               %{sms_resend_disabled_until: future},
               :sms
             )
    end

    test "resend_available?/2 true when disabled_until is in past" do
      past = DateTime.add(DateTime.utc_now(), -30, :second)

      assert ResendRateLimiter.resend_available?(
               %{email_resend_disabled_until: past},
               :email
             )

      assert ResendRateLimiter.resend_available?(
               %{sms_resend_disabled_until: past},
               :sms
             )
    end

    test "resend_seconds_remaining/2 returns 0 for unknown type" do
      assert ResendRateLimiter.resend_seconds_remaining(%{}, :unknown) == 0
    end

    test "resend_seconds_remaining/2 returns 0 when missing assigns" do
      assert ResendRateLimiter.resend_seconds_remaining(%{}, :email) == 0
      assert ResendRateLimiter.resend_seconds_remaining(%{}, :sms) == 0
    end

    test "resend_seconds_remaining/2 returns positive seconds when disabled_until is future" do
      future = DateTime.add(DateTime.utc_now(), 2, :second)

      remaining =
        ResendRateLimiter.resend_seconds_remaining(
          %{email_resend_disabled_until: future},
          :email
        )

      assert remaining in [1, 2]
    end
  end
end
