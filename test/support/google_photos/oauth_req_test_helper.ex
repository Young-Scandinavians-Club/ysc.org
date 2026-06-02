defmodule Ysc.GooglePhotos.OAuth.ReqTestHelper do
  @moduledoc false

  @stub Ysc.GooglePhotos.Api.ReqStub

  def stub, do: @stub

  def token_url?(conn), do: String.ends_with?(conn.request_path, "/token")

  def userinfo_url?(conn), do: String.contains?(conn.request_path, "userinfo")

  def albums_url?(conn), do: String.contains?(conn.request_path, "/v1/albums")

  def ok_token_response(conn, opts \\ []) do
    body =
      %{
        "access_token" => Keyword.get(opts, :access_token, "new-access-token"),
        "expires_in" => Keyword.get(opts, :expires_in, 3600),
        "token_type" => "Bearer"
      }
      |> maybe_put_refresh(Keyword.get(opts, :refresh_token))
      |> maybe_put_scope(Keyword.get(opts, :scope))

    Req.Test.json(conn, body)
  end

  defp maybe_put_refresh(body, nil), do: body
  defp maybe_put_refresh(body, token), do: Map.put(body, "refresh_token", token)

  defp maybe_put_scope(body, nil), do: body
  defp maybe_put_scope(body, scope), do: Map.put(body, "scope", scope)

  def token_error(conn, error, status \\ 400) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(%{"error" => error}))
  end

  def ok_userinfo(conn, email \\ "photos@example.com") do
    Req.Test.json(conn, %{"email" => email})
  end

  def ok_albums(conn) do
    Req.Test.json(conn, %{"albums" => []})
  end
end
