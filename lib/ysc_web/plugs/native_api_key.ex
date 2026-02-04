defmodule YscWeb.Plugs.NativeAPIKey do
  @moduledoc """
  Plug to validate API key for native iOS requests.

  Checks for X-API-Key header and validates it against the configured
  NATIVE_API_KEY environment variable. Only applies to requests with
  swiftui accept format.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # Only validate API key for swiftui format requests
    if accepts_swiftui?(conn) do
      validate_api_key(conn)
    else
      # Skip validation for non-swiftui requests (e.g., HTML)
      conn
    end
  end

  defp accepts_swiftui?(conn) do
    case get_req_header(conn, "accept") do
      [accept_header | _] ->
        String.contains?(accept_header, "swiftui") ||
          String.contains?(
            accept_header,
            "application/vnd.liveviewnative+swiftui"
          )

      _ ->
        false
    end
  end

  defp validate_api_key(conn) do
    # Try to get API key from header first, then from query params as fallback
    api_key =
      case get_req_header(conn, "x-api-key") |> List.first() do
        nil ->
          # Fallback to query parameter (temporary workaround for LiveView Native)
          conn.query_params["api_key"]

        header_key ->
          header_key
      end

    expected_key = Application.get_env(:ysc, :native_api_key)

    cond do
      is_nil(expected_key) || expected_key == "" ->
        # If no API key is configured, allow access (for development)
        conn

      is_nil(api_key) || api_key == "" ->
        # Missing API key
        json = Phoenix.json_library().encode!(%{error: "Missing API key"})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, json)
        |> halt()

      api_key != expected_key ->
        # Invalid API key
        json = Phoenix.json_library().encode!(%{error: "Invalid API key"})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, json)
        |> halt()

      true ->
        # Valid API key
        conn
    end
  end
end
