defmodule YscWeb.Plugs.MobileAPIAuth do
  @moduledoc """
  Plug to authenticate kiosk API requests using a static bearer token.

  Validates the Authorization header (Bearer <token>) against the
  KIOSK_API_KEY environment variable. This is a shared secret used
  by the property kiosk app — no user session is involved.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_token(conn) do
      nil ->
        halt_unauthorized(conn, "Missing authorization token")

      token ->
        expected = Application.get_env(:ysc, :kiosk_api_key)

        cond do
          is_nil(expected) || expected == "" ->
            halt_unauthorized(conn, "Kiosk API key not configured")

          token == expected ->
            conn

          true ->
            halt_unauthorized(conn, "Invalid authorization token")
        end
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> String.trim(token)
      _ -> nil
    end
  end

  defp halt_unauthorized(conn, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: message}))
    |> halt()
  end
end
