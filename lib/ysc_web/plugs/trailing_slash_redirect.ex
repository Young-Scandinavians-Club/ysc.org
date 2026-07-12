defmodule YscWeb.Plugs.TrailingSlashRedirect do
  @moduledoc """
  Redirects request paths that end with a trailing slash to the equivalent
  path without the slash.

  Search engines can treat `/example/123` and `/example/123/` as distinct URLs.
  This plug issues a permanent redirect so only the non-slash form is canonical.

  * `GET` and `HEAD` requests receive `301 Moved Permanently` (SEO-friendly).
  * Other methods receive `308 Permanent Redirect` so the method and body are
    preserved.
  * The root path `/` is left unchanged.
  * Query strings are preserved on the redirect Location.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    path = conn.request_path

    if trailing_slash?(path) do
      location =
        strip_trailing_slash(path) |> with_query_string(conn.query_string)

      status = redirect_status(conn.method)

      conn
      |> put_resp_header("location", location)
      |> send_resp(status, "")
      |> halt()
    else
      conn
    end
  end

  defp trailing_slash?(path), do: path != "/" and String.ends_with?(path, "/")

  defp strip_trailing_slash(path), do: String.trim_trailing(path, "/")

  defp with_query_string(path, ""), do: path
  defp with_query_string(path, query_string), do: path <> "?" <> query_string

  defp redirect_status(method) when method in ["GET", "HEAD"], do: 301
  defp redirect_status(_method), do: 308
end
