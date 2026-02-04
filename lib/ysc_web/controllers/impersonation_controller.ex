defmodule YscWeb.ImpersonationController do
  @moduledoc """
  Admin-only controller for starting and stopping user impersonation.
  """
  use YscWeb, :controller

  alias Ysc.Accounts

  def impersonate(conn, %{"user_id" => user_id}) do
    current_user = conn.assigns.current_user

    unless current_user.role == :admin do
      conn
      |> put_flash(:error, "You do not have permission to impersonate users.")
      |> redirect(to: ~p"/")
      |> halt()
    end

    case Accounts.get_user(user_id) do
      nil ->
        conn
        |> put_flash(:error, "User not found.")
        |> redirect(to: ~p"/admin/users")
        |> halt()

      _target_user ->
        conn
        |> put_session(:impersonated_user_id, user_id)
        |> put_session(:original_admin_id, current_user.id)
        |> put_flash(:info, "Impersonating user. Use the red banner to stop.")
        |> redirect(to: ~p"/")
    end
  end

  def stop_impersonation(conn, _params) do
    # When impersonating, current_user is the impersonated user; require_admin
    # uses real_current_user so we can still reach this action.
    original_admin_id = get_session(conn, :original_admin_id)

    if original_admin_id do
      user_token = get_session(conn, :user_token)
      admin = user_token && Accounts.get_user_by_session_token(user_token)

      if admin && admin.id == original_admin_id && admin.role == :admin do
        conn
        |> delete_session(:impersonated_user_id)
        |> delete_session(:original_admin_id)
        |> put_flash(:info, "Stopped impersonating.")
        |> redirect(to: ~p"/admin")
      else
        conn
        |> delete_session(:impersonated_user_id)
        |> delete_session(:original_admin_id)
        |> put_flash(:info, "Stopped impersonating.")
        |> redirect(to: ~p"/")
      end
    else
      conn
      |> redirect(to: ~p"/")
    end
  end
end
