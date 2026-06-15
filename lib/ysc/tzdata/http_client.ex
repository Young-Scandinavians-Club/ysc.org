defmodule Ysc.Tzdata.HttpClient do
  @moduledoc false

  @behaviour Tzdata.HTTPClient

  @impl true
  def get(url, headers, options) do
    case Req.get(url, req_options(headers, options)) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: body}} ->
        {:ok, {status, normalize_headers(resp_headers), normalize_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def head(url, headers, options) do
    case Req.head(url, req_options(headers, options)) do
      {:ok, %Req.Response{status: status, headers: resp_headers}} ->
        {:ok, {status, normalize_headers(resp_headers)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req_options(headers, options) do
    options
    |> Keyword.take([:follow_redirect])
    |> Keyword.put(:headers, headers)
    |> Keyword.put(:compressed, false)
    |> Keyword.put_new(:redirect, false)
    |> maybe_enable_redirect()
  end

  defp maybe_enable_redirect(opts) do
    if Keyword.get(opts, :follow_redirect, false) do
      opts
      |> Keyword.delete(:follow_redirect)
      |> Keyword.put(:redirect, true)
    else
      Keyword.delete(opts, :follow_redirect)
    end
  end

  defp normalize_headers(headers) do
    Enum.map(headers, fn {k, v} ->
      {to_string(k), header_value_to_string(v)}
    end)
  end

  defp header_value_to_string(v) when is_binary(v), do: v
  defp header_value_to_string(v) when is_list(v), do: Enum.join(v, ", ")
  defp header_value_to_string(v), do: to_string(v)

  defp normalize_body(body) when is_binary(body), do: body
  defp normalize_body(body), do: IO.iodata_to_binary(body)
end
