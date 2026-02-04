defmodule YscWeb.Authorization.EnsureRolePlug do
  @moduledoc """
  Plug for ensuring user has required role.

  Restricts access to routes based on user roles, redirecting unauthorized users.
  """
  import Plug.Conn
  alias Ysc.Accounts.User
  alias Phoenix.Controller

  def init(config), do: config

  def call(conn, roles) do
    user = conn.assigns[:current_user]

    user
    |> has_role?(roles)
    |> maybe_halt(conn)
  end

  defp has_role?(%User{} = user, roles) when is_list(roles) do
    Enum.any?(roles, &has_role?(user, &1))
  end

  defp has_role?(%User{role: role}, role) do
    true
  end

  defp has_role?(_user, _role) do
    false
  end

  defp maybe_halt(true, conn) do
    conn
  end

  defp maybe_halt(_any, conn) do
    conn
    |> Controller.put_flash(:error, "Unauthorized")
    |> Controller.redirect(to: signed_in_path(conn))
    |> halt()
  end

  defp signed_in_path(_conn) do
    "/"
  end
end
