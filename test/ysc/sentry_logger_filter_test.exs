defmodule Ysc.SentryLoggerFilterTest do
  use ExUnit.Case, async: true

  alias Ysc.SentryLoggerFilter

  test "stops ChromicPDF protocol timeout crash reports" do
    exception =
      %ChromicPDF.Browser.ExecutionError{
        message:
          "Timeout in Channel.run_protocol/3!\n\nAdditional diagnostic details"
      }

    event = %{
      level: :error,
      msg: {:string, "Task terminating"},
      meta: %{crash_reason: {exception, []}}
    }

    assert SentryLoggerFilter.discard_chromic_pdf_protocol_timeout(event, []) ==
             :stop
  end

  test "stops the report form of the same timeout" do
    exception =
      %ChromicPDF.Browser.ExecutionError{
        message: "Timeout in Channel.run_protocol/3!"
      }

    event = %{
      level: :error,
      msg: {:report, %{reason: {exception, []}}},
      meta: %{}
    }

    assert SentryLoggerFilter.discard_chromic_pdf_protocol_timeout(event, []) ==
             :stop
  end

  test "allows other ChromicPDF failures and unrelated errors" do
    chromic_error =
      %ChromicPDF.Browser.ExecutionError{
        message: "Browser process exited unexpectedly"
      }

    chromic_event = %{
      level: :error,
      msg: {:report, %{reason: {chromic_error, []}}},
      meta: %{}
    }

    unrelated_event = %{
      level: :error,
      msg: {:string, "Something else failed"},
      meta: %{crash_reason: {%RuntimeError{message: "failure"}, []}}
    }

    assert SentryLoggerFilter.discard_chromic_pdf_protocol_timeout(
             chromic_event,
             []
           ) ==
             :ignore

    assert SentryLoggerFilter.discard_chromic_pdf_protocol_timeout(
             unrelated_event,
             []
           ) ==
             :ignore
  end

  test "stops retryable Locus rate-limit errors" do
    event = %{
      level: :error,
      msg:
        {~c"[locus] [~ts] database failed to load (~p): ~p",
         [:city, :remote, {:http, 429, ~c"Too Many Requests"}]},
      meta: %{}
    }

    assert SentryLoggerFilter.discard_locus_rate_limit(event, []) == :stop
  end

  test "allows other Locus and unrelated errors" do
    locus_error = %{
      level: :error,
      msg:
        {~c"[locus] [~ts] database failed to load (~p): ~p",
         [:city, :remote, {:http, 401, ~c"Unauthorized"}]},
      meta: %{}
    }

    unrelated_rate_limit = %{
      level: :error,
      msg: {~c"API request failed: ~p", [{:http, 429, ~c"Too Many Requests"}]},
      meta: %{}
    }

    assert SentryLoggerFilter.discard_locus_rate_limit(locus_error, []) ==
             :ignore

    assert SentryLoggerFilter.discard_locus_rate_limit(
             unrelated_rate_limit,
             []
           ) ==
             :ignore
  end
end
