defmodule Ysc.SentryUpgradeTest do
  use ExUnit.Case, async: true

  describe "13.5.0 public APIs we use" do
    test "locks the Hex package to 13.5.x" do
      assert to_string(Application.spec(:sentry, :vsn)) == "13.5.0"
    end

    test "capture_exception and capture_message still exist and no-op without a DSN" do
      exception = RuntimeError.exception("sentry upgrade probe")

      assert Sentry.capture_exception(exception, extra: %{probe: true}) ==
               :ignored

      assert Sentry.capture_message("sentry upgrade probe", level: :error) ==
               :ignored
    end

    test "LoggerHandler, PlugCapture, PlugContext, and Scrubber modules still load" do
      assert {:module, Sentry.LoggerHandler} =
               Code.ensure_loaded(Sentry.LoggerHandler)

      assert {:module, Sentry.PlugCapture} =
               Code.ensure_loaded(Sentry.PlugCapture)

      assert {:module, Sentry.PlugContext} =
               Code.ensure_loaded(Sentry.PlugContext)

      assert function_exported?(Sentry.PlugContext, :default_body_scrubber, 1)
      assert is_list(Sentry.Scrubber.default_param_keys())
      assert is_binary(Sentry.Scrubber.scrubbed_value())
    end
  end

  describe "13.5.0 Oban cron check-in callback" do
    test "is unused because we do not enable Sentry.Integrations.Oban" do
      integrations = Sentry.Config.integrations()
      oban_config = Keyword.get(integrations, :oban)

      # The new callback only runs when the Oban cron integration is configured.
      assert oban_config in [nil, []] or
               Keyword.get(oban_config, :should_report_error_check_in_callback) ==
                 nil

      refute Keyword.has_key?(Application.get_all_env(:sentry), :integrations)
    end
  end

  describe "13.5.0 trace context on events" do
    test "omits contexts.trace when OpenTelemetry is not on the process" do
      event =
        Sentry.Event.create_event(
          exception: RuntimeError.exception("no otel span"),
          extra: %{source: "sentry-upgrade"}
        )

      refute Map.has_key?(event.contexts, :trace)
      assert event.original_exception == %RuntimeError{message: "no otel span"}
      assert event.extra.source == "sentry-upgrade"
    end
  end
end
