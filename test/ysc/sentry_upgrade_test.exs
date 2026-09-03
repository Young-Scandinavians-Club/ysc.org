defmodule Ysc.SentryUpgradeTest do
  @moduledoc """
  Guards the sentry 13.5.0 → 13.5.1 upgrade.

  13.5.1 is a patch: rate-limit windows log once at `:log_level`, and
  per-event 429 drops move to `:debug` so host logs are not flooded.
  HTTP 429 no longer records a client report (Sentry counts those
  upstream). Capture, PlugCapture, PlugContext, and Scrubber APIs are
  unchanged. We do not enable Sentry.Integrations.Oban or OpenTelemetry.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Sentry.Transport.RateLimiter

  @transport Path.expand("../../deps/sentry/lib/sentry/transport.ex", __DIR__)
  @rate_limiter Path.expand(
                  "../../deps/sentry/lib/sentry/transport/rate_limiter.ex",
                  __DIR__
                )
  @config Path.expand("../../deps/sentry/lib/sentry/config.ex", __DIR__)

  describe "13.5.1 Hex lock and public APIs" do
    test "locks the Hex package to 13.5.1" do
      assert to_string(Application.spec(:sentry, :vsn)) == "13.5.1"
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

  describe "13.5.1 Oban cron check-in callback" do
    test "is unused because we do not enable Sentry.Integrations.Oban" do
      integrations = Sentry.Config.integrations()
      oban_config = Keyword.get(integrations, :oban)

      # The 13.5.0 callback only runs when the Oban cron integration is configured.
      assert oban_config in [nil, []] or
               Keyword.get(oban_config, :should_report_error_check_in_callback) ==
                 nil

      refute Keyword.has_key?(Application.get_all_env(:sentry), :integrations)
    end
  end

  describe "13.5.1 trace context on events" do
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

  describe "13.5.1 rate-limit logging" do
    test "announces a category limit once and treats a repeat as an extension" do
      table = :"sentry_rate_limiter_#{System.unique_integer([:positive])}"
      start_supervised!({RateLimiter, name: table})
      Process.put(:rate_limiter_table_name, table)
      on_exit(fn -> Process.delete(:rate_limiter_table_name) end)

      first =
        capture_log(fn ->
          assert :ok = RateLimiter.update_rate_limits("60:error")
        end)

      assert first =~ "rate-limiting"
      assert first =~ ~s(the "error" data category)
      assert RateLimiter.rate_limited?("error")

      second =
        capture_log(fn ->
          assert :ok = RateLimiter.update_rate_limits("60:error")
        end)

      refute second =~ "rate-limiting"
      assert RateLimiter.rate_limited?("error")
    end

    test "transport skips client reports on HTTP 429 and debugs per-event drops" do
      transport = File.read!(@transport)
      rate_limiter = File.read!(@rate_limiter)
      config = File.read!(@config)

      assert transport =~ "A 429 is counted upstream"
      refute transport =~ ~r/\{:error, :rate_limited\} ->\s+ClientReport/

      assert transport =~
               "defp log_send_result({:error, %ClientError{reason: :rate_limited}"

      assert transport =~ "LoggerUtils.debug"

      assert rate_limiter =~ "defp log_new_limits"
      assert rate_limiter =~ "Sentry is rate-limiting "

      assert config =~ "Rate limits are the exception"
      assert config =~ "domain: [:sentry]"
    end
  end
end
