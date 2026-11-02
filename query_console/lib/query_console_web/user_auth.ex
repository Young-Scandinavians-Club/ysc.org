defmodule QueryConsoleWeb.UserAuth do
  @moduledoc """
  Session-based auth plugs and LiveView on_mount hooks.
  """

  use QueryConsoleWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias QueryConsole.Accounts

  # The console only holds a shadow user, so it cannot see a later role or state
  # change in YSC. Capping the session age forces a fresh SSO round trip (which
  # re-checks role and state in YSC) at least this often, and bounds how long a
  # copied session cookie stays usable.
  @default_session_ttl_seconds 4 * 60 * 60

  @doc "Maximum age of a console session, in seconds."
  def session_ttl_seconds do
    Application.get_env(
      :query_console,
      :session_ttl_seconds,
      @default_session_ttl_seconds
    )
  end

  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> put_session(:authenticated_at, now_unix())
  end

  def log_out_user(conn) do
    conn
    |> renew_session()
    |> delete_session(:user_id)
    |> delete_session(:authenticated_at)
  end

  def fetch_current_user(conn, _opts) do
    user =
      user_from_session(%{
        "user_id" => get_session(conn, :user_id),
        "authenticated_at" => get_session(conn, :authenticated_at)
      })

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
      {:cont, attach_session_expiry(socket, session)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/auth/ysc")}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      user_from_session(session)
    end)
  end

  # Returns the shadow user only while the session is younger than the TTL.
  # Sessions without `authenticated_at` (issued before the TTL existed) are
  # treated as expired.
  defp user_from_session(%{"user_id" => user_id} = session)
       when is_binary(user_id) do
    if session_fresh?(session["authenticated_at"]) do
      Accounts.get_user(user_id)
    end
  end

  defp user_from_session(_session), do: nil

  defp session_fresh?(authenticated_at) when is_integer(authenticated_at) do
    age = now_unix() - authenticated_at
    age >= 0 and age < session_ttl_seconds()
  end

  defp session_fresh?(_), do: false

  # A mounted LiveView never re-runs on_mount, so without this an open console
  # tab would outlive its session. Send ourselves a message when the session
  # runs out and bounce through SSO, which re-checks the YSC role and state.
  defp attach_session_expiry(socket, session) do
    authenticated_at = session["authenticated_at"]

    if Phoenix.LiveView.connected?(socket) and is_integer(authenticated_at) do
      remaining_ms = max(authenticated_at + session_ttl_seconds() - now_unix(), 0) * 1000
      Process.send_after(self(), :query_console_session_expired, remaining_ms + 500)

      Phoenix.LiveView.attach_hook(socket, :session_expiry, :handle_info, fn
        :query_console_session_expired, socket ->
          {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/auth/ysc")}

        _message, socket ->
          {:cont, socket}
      end)
    else
      socket
    end
  end

  defp now_unix, do: System.os_time(:second)

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
