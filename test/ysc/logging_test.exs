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
