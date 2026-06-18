defmodule Ysc.ResendRateLimiterTest do
  use ExUnit.Case, async: false

  alias Ysc.ResendRateLimiter

  setup do
    # Unique per test so parallel runs do not delete each other's cache keys.
    id = System.unique_integer([:positive])
    email_key = "resend_email:#{id}"
    sms_key = "resend_sms:#{id}"

    Cachex.del(:ysc_cache, email_key)
    Cachex.del(:ysc_cache, sms_key)

    on_exit(fn ->
      Cachex.del(:ysc_cache, email_key)
      Cachex.del(:ysc_cache, sms_key)
    end)

    {:ok, id: id}
  end

  describe "resend_allowed?/3 and record_resend/3" do
    test "allows when no cache entry exists", %{id: id} do
      assert {:ok, :allowed} = ResendRateLimiter.resend_allowed?(id, :email, 60)
      assert ResendRateLimiter.remaining_seconds(id, :email, 60) == 0
    end

    test "rate limits after record_resend/3", %{id: id} do
      assert :ok = ResendRateLimiter.record_resend(id, :email, 60)

      assert {:error, :rate_limited, remaining} =
               ResendRateLimiter.resend_allowed?(id, :email, 60)

      assert is_integer(remaining)
      assert remaining > 0
    end

    test "check_and_record_resend/3 records when allowed", %{id: id} do
      assert {:ok, :allowed} =
               ResendRateLimiter.check_and_record_resend(id, :sms, 60)

      assert {:error, :rate_limited, _} =
               ResendRateLimiter.check_and_record_resend(id, :sms, 60)
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

    test "resend_seconds_remaining/2 returns 0 when disabled_until is in the past" do
      past = DateTime.add(DateTime.utc_now(), -5, :second)

      assert ResendRateLimiter.resend_seconds_remaining(
               %{email_resend_disabled_until: past},
               :email
             ) == 0

      assert ResendRateLimiter.resend_seconds_remaining(
               %{sms_resend_disabled_until: past},
               :sms
             ) == 0
    end
  end
end

defmodule Ysc.ResendRateLimiterCacheFailureTest do
  use ExUnit.Case, async: false

  alias Ysc.ResendRateLimiter

  setup do
    on_exit(fn ->
      if Process.whereis(:ysc_cache) == nil do
        assert {:ok, _} =
                 Supervisor.start_child(
                   Ysc.Supervisor,
                   {Cachex, name: :ysc_cache}
                 )
      end
    end)

    :ok
  end

  test "record_resend/3 returns ok when Cachex.put fails" do
    assert :ok = Supervisor.terminate_child(Ysc.Supervisor, Cachex)
    assert :ok = Supervisor.delete_child(Ysc.Supervisor, Cachex)

    try do
      assert :ok = ResendRateLimiter.record_resend(999_001, :email, 60)
    after
      assert {:ok, _} =
               Supervisor.start_child(
                 Ysc.Supervisor,
                 {Cachex, name: :ysc_cache}
               )
    end
  end
end
