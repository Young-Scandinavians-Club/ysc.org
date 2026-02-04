defmodule YscWeb.Layouts do
  use YscWeb, :html

  embed_templates "layouts/*"

  def fullscreen?(conn_or_path) when is_binary(conn_or_path) do
    String.starts_with?(conn_or_path, [
      "/users/log-in",
      "/users/register",
      "/users/reset-password",
      "/users/settings/confirm-email",
      "/users/log-in/auto",
      "/account/setup",
      "/report-conduct-violation"
    ])
  end

  def fullscreen?(%Plug.Conn{} = conn) do
    current_path = Path.join(["/" | conn.path_info])
    fullscreen?(current_path)
  end

  def fullscreen?(_), do: false

  def hero_mode?(conn_or_path, current_user) when is_binary(conn_or_path) do
    cond do
      # Home page with no user logged in
      conn_or_path == "/" && current_user == nil ->
        true

      # Booking pages (both logged in and not logged in)
      String.starts_with?(conn_or_path, "/bookings/tahoe") ->
        true

      String.starts_with?(conn_or_path, "/bookings/clear-lake") ->
        true

      true ->
        false
    end
  end

  def hero_mode?(%Plug.Conn{} = conn, current_user) do
    current_path = Path.join(["/" | conn.path_info])
    hero_mode?(current_path, current_user)
  end

  def hero_mode?(_, _), do: false
end
