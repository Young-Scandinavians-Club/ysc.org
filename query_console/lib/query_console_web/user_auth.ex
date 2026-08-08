defmodule QueryConsoleWeb.UserAuth do
  @moduledoc """
  Session-based auth plugs and LiveView on_mount hooks.
  """

  use QueryConsoleWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias QueryConsole.Accounts

  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
  end

  def log_out_user(conn) do
    conn
    |> renew_session()
    |> delete_session(:user_id)
  end

  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Accounts.get_user(user_id)
    assign(conn, :current_user, user)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      # Silent redirect into SSO — unauthenticated visits are the normal entry path.
      # Avoid putting an error flash here; it would survive into the post-login page
      # (clear_session does not clear conn.assigns.flash loaded by fetch_live_flash).
      conn
      |> redirect(to: ~p"/auth/ysc")
      |> halt()
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/auth/ysc")}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_id = session["user_id"] do
        Accounts.get_user(user_id)
      end
    end)
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
