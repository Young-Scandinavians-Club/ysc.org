defmodule YscWeb.Authorization.EnsureApprovedUserPlug do
  @moduledoc """
  Plug for ensuring user account is approved.

  Restricts access to routes for users whose accounts are not yet approved.
  """
  import Plug.Conn
  alias Phoenix.Controller

  def init(config), do: config

  def call(conn) do
    user = conn.assigns[:current_user]

    user
    |> approved?()
    |> maybe_halt(conn)
  end

  def approved?(user) do
    user.state == :active
  end

  defp maybe_halt(true, conn) do
    conn
  end

  defp maybe_halt(_any, conn) do
    conn
    |> Controller.put_flash(:error, "Your account is pending approval")
    |> Controller.redirect(to: not_approved_path(conn))
    |> halt()
  end

  defp not_approved_path(_conn) do
    "/pending-review"
  end
end
