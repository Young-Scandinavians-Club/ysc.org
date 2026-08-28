defmodule YscWeb.ImpersonationController do
  @moduledoc """
  Admin-only controller for starting and stopping user impersonation.
  """
  use YscWeb, :controller

  alias Ysc.Accounts

  def impersonate(conn, %{"user_id" => user_id}) do
    # Prefer real_current_user so a nested impersonate attempt cannot record the
    # victim as original_admin_id.
    current_user =
      conn.assigns[:real_current_user] || conn.assigns.current_user

    case Accounts.get_user(user_id) do
      nil ->
        conn
        |> YscWeb.Flash.put_toast(:error, "User not found.",
          title: "Impersonation"
        )
        |> redirect(to: ~p"/admin/users")
        |> halt()

      _target_user ->
        # Drop any post-login / OAuth reauth grace period. Otherwise the
        # admin's own recent step-up would satisfy reauth_still_valid?/1 while
        # acting as the victim and allow password/email/phone changes without
        # the victim's credentials (Finding 47).
        conn
        |> delete_session(:reauth_verified_at)
        |> put_session(:impersonated_user_id, user_id)
        |> put_session(:original_admin_id, current_user.id)
        |> YscWeb.Flash.put_toast(
          :info,
          "Impersonating user. Use the red banner to stop.",
          title: "Impersonation"
        )
        |> redirect(to: ~p"/")
    end
  end

  def stop_impersonation(conn, _params) do
    # When impersonating, current_user is the impersonated user; require_admin
    # uses real_current_user so we can still reach this action.
    original_admin_id = get_session(conn, :original_admin_id)
    impersonated_user_id = get_session(conn, :impersonated_user_id)

    if original_admin_id do
      user_token = get_session(conn, :user_token)
      admin = user_token && Accounts.get_user_by_session_token(user_token)

      redirect_to =
        if admin && admin.id == original_admin_id && admin.role == :admin &&
             impersonated_user_id do
          ~p"/admin/users/#{impersonated_user_id}/details"
        else
          if admin && admin.id == original_admin_id && admin.role == :admin,
            do: ~p"/admin",
            else: ~p"/"
        end

      conn
      |> delete_session(:impersonated_user_id)
      |> delete_session(:original_admin_id)
      |> YscWeb.Flash.put_toast(:info, "Stopped impersonating.",
        title: "Impersonation"
      )
      |> redirect(to: redirect_to)
    else
      conn
      |> redirect(to: ~p"/")
    end
  end
end
