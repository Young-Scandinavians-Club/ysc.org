defmodule YscWeb.Plugs.IpRateLimit do
  @moduledoc """
  Shared IP rate-limit plug. Named wrappers pass a limiter and response format:

      plug YscWeb.Plugs.IpRateLimit, limiter: Ysc.AuthRateLimit, format: :html

  ## Options

    * `:limiter` — module exporting `check_ip/1` (required)
    * `:format` — `:html`, `:json`, or `:text` (default `:json`)
  """
  import Plug.Conn

  def init(opts), do: opts

  # sobelow_skip ["XSS.SendResp"]
  def call(conn, opts) do
    limiter = Keyword.fetch!(opts, :limiter)
    format = Keyword.get(opts, :format, :json)

    case limiter.check_ip(conn.remote_ip) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after_sec} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_sec))
        |> send_limited(format, retry_after_sec)
        |> halt()
    end
  end

  defp send_limited(conn, :html, retry_after_sec) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(429, html_body(retry_after_sec))
  end

  defp send_limited(conn, :json, _retry_after_sec) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(429, Jason.encode!(%{error: "Too many requests"}))
  end

  defp send_limited(conn, :text, _retry_after_sec) do
    send_resp(conn, 429, "Too many requests")
  end

  defp html_body(retry_after_sec) do
    """
    <!DOCTYPE html>
    <html>
    <head><title>Too Many Requests</title></head>
    <body>
    <h1>Too many attempts</h1>
    <p>Please try again in #{retry_after_sec} seconds.</p>
    </body>
    </html>
    """
  end
end
