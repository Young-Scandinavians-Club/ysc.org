defmodule Ysc.SentryLoggerFilter do
  @moduledoc false

  @chromic_pdf_protocol_timeout "Timeout in Channel.run_protocol/3!"
  @locus_log_prefix ~c"[locus]"

  @doc false
  def discard_chromic_pdf_protocol_timeout(log_event, _extra) do
    if chromic_pdf_protocol_timeout?(log_event) do
      :stop
    else
      :ignore
    end
  end

  @doc false
  def discard_locus_rate_limit(log_event, _extra) do
    if locus_rate_limit?(log_event) do
      :stop
    else
      :ignore
    end
  end

  defp chromic_pdf_protocol_timeout?(%{meta: meta, msg: msg}) do
    timeout_reason?(Map.get(meta, :crash_reason)) or timeout_report?(msg)
  end

  defp chromic_pdf_protocol_timeout?(_log_event), do: false

  defp timeout_report?({:report, report})
       when is_map(report) or is_list(report) do
    report
    |> Map.new()
    |> Map.get(:reason)
    |> timeout_reason?()
  end

  defp timeout_report?(_message), do: false

  defp timeout_reason?(
         {%{
            __struct__: ChromicPDF.Browser.ExecutionError,
            message: @chromic_pdf_protocol_timeout <> _
          }, stacktrace}
       )
       when is_list(stacktrace),
       do: true

  defp timeout_reason?(_reason), do: false

  defp locus_rate_limit?(%{msg: {format, arguments}})
       when is_list(format) and is_list(arguments) do
    List.starts_with?(format, @locus_log_prefix) and
      Enum.any?(arguments, &http_rate_limit?/1)
  end

  defp locus_rate_limit?(_log_event), do: false

  defp http_rate_limit?({:http, 429, _body}), do: true
  defp http_rate_limit?({:http, 429, _headers, _body}), do: true
  defp http_rate_limit?(_reason), do: false
end
