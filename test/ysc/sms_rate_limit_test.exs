defmodule Ysc.SmsRateLimitTest do
  @moduledoc """
  Comprehensive tests for SMS rate limiting functionality.

  Tests verify:
  - Per-minute rate limiting (5 SMS max)
  - Per-hour rate limiting (20 SMS max)
  - Multiple phone number isolation
  - Cache-based timestamp tracking
  - Status reporting accuracy
  """
  use Ysc.DataCase, async: true

  alias Ysc.SmsRateLimit

  setup do
    # Clear cache before each test to ensure clean state
    Cachex.clear(:ysc_cache)
    :ok
  end

  describe "check_rate_limit/1" do
    test "allows SMS when cache is empty" do
      phone_number = "12065551234"

      assert {:ok, :allowed} = SmsRateLimit.check_rate_limit(phone_number)
    end

    test "allows SMS when under per-minute limit" do
      phone_number = "12065551234"

      # Record 4 SMS (under the limit of 5)
      Enum.each(1..4, fn _ ->
        SmsRateLimit.record_sms_send(phone_number)
        # Small delay to ensure different timestamps
        Process.sleep(10)
      end)

      assert {:ok, :allowed} = SmsRateLimit.check_rate_limit(phone_number)
    end

    test "allows SMS when under per-hour limit (spread over time)" do
      phone_number = "12065551234"
      cache_key = "sms_rate_limit:#{phone_number}"
      now = DateTime.utc_now() |> DateTime.to_unix(:second)

      # Manually create 19 timestamps spread over the last hour
      # 4 in the last minute, 15 older than a minute but within the hour
      timestamps = [
        # 4 recent (within last minute) - under the limit of 5
        now - 10,
        now - 20,
        now - 30,
        now - 40,
        # 15 older (within hour, outside minute)
        now - 70,
        now - 100,
        now - 200,
        now - 300,
        now - 400,
        now - 500,
        now - 600,
        now - 700,
        now - 800,
        now - 900,
        now - 1000,
        now - 1200,
        now - 1500,
        now - 1800,
        now - 2000
      ]

      Cachex.put(:ysc_cache, cache_key, timestamps, ttl: 60 * 60 * 1000)

      # Should be allowed (19 < 20 per hour, and only 4 in last minute)
      assert {:ok, :allowed} = SmsRateLimit.check_rate_limit(phone_number)
    end

    test "blocks SMS when per-minute limit is exceeded" do
      phone_number = "12065551234"

      # Record 5 SMS (at the limit)
      Enum.each(1..5, fn _ ->
        SmsRateLimit.record_sms_send(phone_number)
        Process.sleep(10)
      end)

      # 6th SMS should be blocked
      assert {:error, :rate_limit_exceeded, reason} =
               SmsRateLimit.check_rate_limit(phone_number)

      assert reason =~ "maximum 5 SMS per minute"
    end

    test "blocks SMS when per-hour limit is exceeded" do
      phone_number = "12065551234"
      cache_key = "sms_rate_limit:#{phone_number}"
      now = DateTime.utc_now() |> DateTime.to_unix(:second)

      # Manually create 20 timestamps spread over the last hour
      # 4 in the last minute (under per-minute limit), 16 older than a minute but within the hour
      timestamps = [
        # 4 recent (within last minute) - under the limit of 5
        now - 10,
        now - 20,
        now - 30,
        now - 40,
        # 16 older (within hour, outside minute)
        now - 70,
        now - 100,
        now - 200,
        now - 300,
        now - 400,
        now - 500,
        now - 600,
        now - 700,
        now - 800,
        now - 900,
        now - 1000,
        now - 1200,
        now - 1500,
        now - 1800,
        now - 2000,
        now - 2500
      ]

      Cachex.put(:ysc_cache, cache_key, timestamps, ttl: 60 * 60 * 1000)

      # 21st SMS should be blocked by per-hour limit (20 already sent)
      assert {:error, :rate_limit_exceeded, reason} =
               SmsRateLimit.check_rate_limit(phone_number)

      assert reason =~ "maximum 20 SMS per hour"
    end

    test "per-minute limit takes precedence over per-hour limit" do
      phone_number = "12065551234"

      # Record 5 SMS quickly (within a minute)
      Enum.each(1..5, fn _ ->
        SmsRateLimit.record_sms_send(phone_number)
        Process.sleep(10)
      end)

      # Should be blocked by per-minute limit, not per-hour
      assert {:error, :rate_limit_exceeded, reason} =
               SmsRateLimit.check_rate_limit(phone_number)

      assert reason =~ "per minute"
    end

    test "isolates rate limits per phone number" do
      phone1 = "12065551234"
      phone2 = "12065551235"

      # Exceed limit for phone1
      Enum.each(1..5, fn _ ->
        SmsRateLimit.record_sms_send(phone1)
        Process.sleep(10)
      end)

      # Phone2 should still be allowed
      assert {:ok, :allowed} = SmsRateLimit.check_rate_limit(phone2)

      # Phone1 should be blocked
      assert {:error, :rate_limit_exceeded, _} =
               SmsRateLimit.check_rate_limit(phone1)
    end

    test "filters out timestamps older than 1 hour" do
      phone_number = "12065551234"
      cache_key = "sms_rate_limit:#{phone_number}"
      now = DateTime.utc_now() |> DateTime.to_unix(:second)

      # Manually insert old timestamps (older than 1 hour)
      old_timestamps = [
        # 1 hour 1 minute ago
        now - 3700,
        # 2 hours ago
        now - 7200
      ]

      Cachex.put(:ysc_cache, cache_key, old_timestamps, ttl: 60 * 60 * 1000)

      # Should be allowed since old timestamps are filtered out
      assert {:ok, :allowed} = SmsRateLimit.check_rate_limit(phone_number)
    end
  end

  describe "record_sms_send/1" do
    test "records SMS send in cache" do
      phone_number = "12065551234"

      assert :ok = SmsRateLimit.record_sms_send(phone_number)

      # Verify it was recorded
      cache_key = "sms_rate_limit:#{phone_number}"
      {:ok, timestamps} = Cachex.get(:ysc_cache, cache_key)
      assert is_list(timestamps)
      assert length(timestamps) == 1
    end

    test "appends new timestamp to existing list" do
      phone_number = "12065551234"

      # Record first SMS
      SmsRateLimit.record_sms_send(phone_number)
      Process.sleep(10)

      # Record second SMS
      SmsRateLimit.record_sms_send(phone_number)

      # Verify both timestamps are present
      cache_key = "sms_rate_limit:#{phone_number}"
      {:ok, timestamps} = Cachex.get(:ysc_cache, cache_key)
      assert length(timestamps) == 2
      assert Enum.all?(timestamps, &is_integer/1)
    end

    test "filters out old timestamps when recording" do
      phone_number = "12065551234"
      cache_key = "sms_rate_limit:#{phone_number}"
      now = DateTime.utc_now() |> DateTime.to_unix(:second)

      # Manually insert old timestamps
      old_timestamps = [
        # 1 hour 1 minute ago
        now - 3700,
        # 100 seconds ago (within hour)
        now - 100
      ]

      Cachex.put(:ysc_cache, cache_key, old_timestamps, ttl: 60 * 60 * 1000)

      # Record new SMS
      SmsRateLimit.record_sms_send(phone_number)

      # Should only have the recent timestamp and the new one
      {:ok, timestamps} = Cachex.get(:ysc_cache, cache_key)
      assert length(timestamps) == 2
      # All timestamps should be within the last hour
      assert Enum.all?(timestamps, fn ts -> ts > now - 3600 end)
    end

    test "handles multiple phone numbers independently" do
      phone1 = "12065551234"
      phone2 = "12065551235"

      SmsRateLimit.record_sms_send(phone1)
      # Small delay to ensure different timestamps
      Process.sleep(10)
      SmsRateLimit.record_sms_send(phone2)

      # Both should be recorded separately
      {:ok, timestamps1} = Cachex.get(:ysc_cache, "sms_rate_limit:#{phone1}")
      {:ok, timestamps2} = Cachex.get(:ysc_cache, "sms_rate_limit:#{phone2}")

      assert length(timestamps1) == 1
      assert length(timestamps2) == 1
      # Verify they're stored in different cache keys
      assert Cachex.exists?(:ysc_cache, "sms_rate_limit:#{phone1}")
      assert Cachex.exists?(:ysc_cache, "sms_rate_limit:#{phone2}")
    end
  end

  describe "get_rate_limit_status/1" do
    test "returns zero counts for empty cache" do
      phone_number = "12065551234"

      status = SmsRateLimit.get_rate_limit_status(phone_number)

      assert status.minute_count == 0
      assert status.hour_count == 0
      assert status.minute_limit == 5
      assert status.hour_limit == 20
      assert status.minute_remaining == 5
      assert status.hour_remaining == 20
    end

    test "returns accurate counts for recent SMS" do
      phone_number = "12065551234"

      # Record 3 SMS
      Enum.each(1..3, fn _ ->
        SmsRateLimit.record_sms_send(phone_number)
        Process.sleep(10)
      end)

      status = SmsRateLimit.get_rate_limit_status(phone_number)

      assert status.minute_count == 3
      assert status.hour_count == 3
      assert status.minute_remaining == 2
      assert status.hour_remaining == 17
    end

    test "returns accurate counts at per-minute limit" do
      phone_number = "12065551234"

      # Record 5 SMS (at the limit)
      Enum.each(1..5, fn _ ->
        SmsRateLimit.record_sms_send(phone_number)
        Process.sleep(10)
      end)

      status = SmsRateLimit.get_rate_limit_status(phone_number)

      assert status.minute_count == 5
      assert status.minute_remaining == 0
    end

    test "returns accurate counts at per-hour limit" do
      phone_number = "12065551234"
      cache_key = "sms_rate_limit:#{phone_number}"
      now = DateTime.utc_now() |> DateTime.to_unix(:second)

      # Manually create 20 timestamps spread over the last hour
      timestamps = Enum.map(1..20, fn i -> now - i * 100 end)
      Cachex.put(:ysc_cache, cache_key, timestamps, ttl: 60 * 60 * 1000)

      status = SmsRateLimit.get_rate_limit_status(phone_number)

      assert status.hour_count == 20
      assert status.hour_remaining == 0
    end

    test "filters out old timestamps from counts" do
      phone_number = "12065551234"
      cache_key = "sms_rate_limit:#{phone_number}"
      now = DateTime.utc_now() |> DateTime.to_unix(:second)

      # Manually insert mix of old and recent timestamps
      timestamps = [
        # 1 hour 1 minute ago (should be filtered)
        now - 3700,
        # 100 seconds ago (within hour, outside minute)
        now - 100,
        # 30 seconds ago (within minute)
        now - 30,
        # 10 seconds ago (within minute)
        now - 10
      ]

      Cachex.put(:ysc_cache, cache_key, timestamps, ttl: 60 * 60 * 1000)

      status = SmsRateLimit.get_rate_limit_status(phone_number)

      # Should only count timestamps within the windows
      # last 2 timestamps
      assert status.minute_count == 2
      # last 3 timestamps (excluding the very old one)
      assert status.hour_count == 3
    end

    test "returns correct remaining counts" do
      phone_number = "12065551234"

      # Record 2 SMS
      Enum.each(1..2, fn _ ->
        SmsRateLimit.record_sms_send(phone_number)
        Process.sleep(10)
      end)

      status = SmsRateLimit.get_rate_limit_status(phone_number)

      # 5 - 2
      assert status.minute_remaining == 3
      # 20 - 2
      assert status.hour_remaining == 18
    end

    test "never returns negative remaining counts" do
      phone_number = "12065551234"
      cache_key = "sms_rate_limit:#{phone_number}"
      now = DateTime.utc_now() |> DateTime.to_unix(:second)

      # Manually insert more than the limit (shouldn't happen in practice, but test edge case)
      timestamps = Enum.map(1..25, fn _ -> now - :rand.uniform(100) end)
      Cachex.put(:ysc_cache, cache_key, timestamps, ttl: 60 * 60 * 1000)

      status = SmsRateLimit.get_rate_limit_status(phone_number)

      # Remaining should never be negative
      assert status.minute_remaining >= 0
      assert status.hour_remaining >= 0
    end
  end

  describe "integration: check and record flow" do
    test "allows sending SMS up to limits" do
      phone_number = "12065551234"

      # Send 4 SMS (under limit)
      Enum.each(1..4, fn _ ->
        assert {:ok, :allowed} = SmsRateLimit.check_rate_limit(phone_number)
        SmsRateLimit.record_sms_send(phone_number)
        Process.sleep(10)
      end)

      # 5th should still be allowed
      assert {:ok, :allowed} = SmsRateLimit.check_rate_limit(phone_number)
    end

    test "blocks after reaching per-minute limit" do
      phone_number = "12065551234"

      # Send 5 SMS
      Enum.each(1..5, fn _ ->
        assert {:ok, :allowed} = SmsRateLimit.check_rate_limit(phone_number)
        SmsRateLimit.record_sms_send(phone_number)
        Process.sleep(10)
      end)

      # 6th should be blocked
      assert {:error, :rate_limit_exceeded, _} =
               SmsRateLimit.check_rate_limit(phone_number)
    end

    test "status reflects current state accurately" do
      phone_number = "12065551234"

      # Send 3 SMS
      Enum.each(1..3, fn _ ->
        SmsRateLimit.record_sms_send(phone_number)
        Process.sleep(10)
      end)

      status = SmsRateLimit.get_rate_limit_status(phone_number)
      assert status.minute_count == 3
      assert status.hour_count == 3

      # Check should still allow
      assert {:ok, :allowed} = SmsRateLimit.check_rate_limit(phone_number)
    end
  end
end
