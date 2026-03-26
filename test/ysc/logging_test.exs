defmodule Ysc.LoggingTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  require Ysc.Logging

  setup do
    # Temporarily allow all log levels for these tests
    original_level = Logger.level()
    Logger.configure(level: :debug)

    on_exit(fn ->
      Logger.configure(level: original_level)
    end)

    :ok
  end

  describe "helpers (unit)" do
    test "normalize_opts/1 converts maps to keyword lists" do
      kw = Ysc.Logging.normalize_opts(%{a: 1, b: 2})
      assert Enum.sort(kw) == [a: 1, b: 2]
    end

    test "normalize_opts/1 passes through keyword lists" do
      assert Ysc.Logging.normalize_opts(foo: :bar) == [foo: :bar]
    end

    test "maybe_put_sentry_opt/3 skips nil values" do
      assert Ysc.Logging.maybe_put_sentry_opt([], :x, nil) == []
    end

    test "maybe_put_sentry_opt/3 puts non-nil values" do
      assert Ysc.Logging.maybe_put_sentry_opt([], :x, :y) == [x: :y]
    end

    test "maybe_merge_extra/2 returns base when extra is nil" do
      assert Ysc.Logging.maybe_merge_extra(%{a: 1}, nil) == %{a: 1}
    end

    test "maybe_merge_extra/2 merges maps" do
      assert Ysc.Logging.maybe_merge_extra(%{a: 1}, %{b: 2}) == %{a: 1, b: 2}
    end

    test "build_error_metadata/3 uses inspect for non-exception errors" do
      opts = [user_id: 1]
      result = Ysc.Logging.build_error_metadata(opts, :bad, nil)
      assert Keyword.get(result, :user_id) == 1
      assert Keyword.get(result, :error) == inspect(:bad)
    end

    test "build_error_metadata/3 uses Exception.message for exceptions" do
      err = ArgumentError.exception("nope")
      opts = [user_id: 1]
      result = Ysc.Logging.build_error_metadata(opts, err, nil)
      assert Keyword.get(result, :user_id) == 1
      assert Keyword.get(result, :error) == "nope"
    end

    test "build_error_metadata/3 adds stacktrace when present" do
      opts = []
      st = [{Test, :fun, 1, []}]
      result = Ysc.Logging.build_error_metadata(opts, :x, st)
      assert Keyword.has_key?(result, :stacktrace)
    end

    test "build_error_metadata/3 returns opts unchanged when error is nil" do
      opts = [booking_id: "b1"]
      assert Ysc.Logging.build_error_metadata(opts, nil, []) == opts
    end

    test "capture_sentry/6 returns :ok when error is nil" do
      assert :ok ==
               Ysc.Logging.capture_sentry(nil, [], nil, nil, "msg", [])
    end
  end

  describe "test environment behavior" do
    test "logging still emits to Logger in test environment" do
      # Logs should still be emitted so tests can verify logging behavior
      log = capture_log(fn -> Ysc.Logging.info("Test info message") end)
      assert log =~ "Test info message"

      log = capture_log(fn -> Ysc.Logging.warning("Test warning") end)
      assert log =~ "Test warning"

      log =
        capture_log([level: :debug], fn -> Ysc.Logging.debug("Test debug") end)

      assert log =~ "Test debug"
    end

    test "error logging emits to Logger without Sentry in test environment" do
      # Error logs should be emitted but not sent to Sentry during tests
      log = capture_log(fn -> Ysc.Logging.error("Test error") end)
      assert log =~ "Test error"
    end

    test "error logging with exception logs but skips Sentry in test environment" do
      error = RuntimeError.exception("Test runtime error")

      log =
        capture_log(fn ->
          Ysc.Logging.error("Failed to process",
            error: error,
            stacktrace: [],
            entity_id: 456,
            extra: %{test: true},
            tags: %{env: "test"}
          )
        end)

      # Should log the message and error details
      assert log =~ "Failed to process"
      assert log =~ "Test runtime error"
    end

    test "logging with metadata works in test environment" do
      log =
        capture_log(fn ->
          Ysc.Logging.info("User action", user_id: 123, action: "login")
        end)

      assert log =~ "User action"
      assert log =~ "user_id=123"

      log =
        capture_log(fn ->
          Ysc.Logging.warning("Rate limit", current: 90, max: 100)
        end)

      assert log =~ "Rate limit"
    end
  end
end
