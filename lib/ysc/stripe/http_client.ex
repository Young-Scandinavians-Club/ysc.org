defmodule Ysc.Stripe.HttpClient do
  @moduledoc false

  # Hackney-compatible HTTP adapter for stripity_stripe.
  #
  # stripity_stripe sends `Connection: keep-alive` in add_common_headers/1, which
  # triggers :protocol_error on hackney 4.x. Req handles the same headers correctly.

  @spec request(
          atom(),
          String.t(),
          [{String.t(), String.t()}],
          term(),
          keyword()
        ) ::
          {:ok, non_neg_integer(), [{String.t(), String.t()}], binary()}
          | {:error, term()}
  def request(method, url, headers, body, _opts) do
    case Req.request(build_request(method, url, headers, body)) do
      {:ok,
       %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, status, normalize_headers(resp_headers),
         normalize_body(resp_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_request(method, url, headers, body) do
    [
      method: method,
      url: url,
      headers: headers,
      redirect: false,
      compressed: false,
      decode_body: false
    ]
    |> put_body(body)
    |> Keyword.merge(Application.get_env(:ysc, :stripe_http_req_opts, []))
  end

  defp put_body(req_opts, {:multipart, parts}) do
    Keyword.put(req_opts, :form_multipart, multipart_parts(parts))
  end

  # stripity_stripe passes "" for GET bodies (params are already in the query
  # string). Skip empty bodies so GET/DELETE stay bodyless. Req 0.7.0–0.7.2
  # rewrote GET/DELETE with a body into POST (Stripe rejects that); 0.7.3 reverted it.
  defp put_body(req_opts, body) when body in [nil, ""], do: req_opts

  defp put_body(req_opts, body) do
    Keyword.put(req_opts, :body, body)
  end

  defp multipart_parts(parts) do
    Enum.map(parts, fn
      {key, value} -> {to_string(key), value}
      other -> other
    end)
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
  defp normalize_body(body) when is_map(body), do: Jason.encode!(body)
  defp normalize_body(body), do: IO.iodata_to_binary(body)
end
