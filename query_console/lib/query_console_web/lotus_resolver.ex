defmodule QueryConsoleWeb.LotusResolver do
  @moduledoc """
  Bridges query-console session auth into Lotus Web access control.
  """

  @behaviour Lotus.Web.Resolver

  @impl Lotus.Web.Resolver
  def resolve_user(conn) do
    conn.assigns[:current_user]
  end

  @impl Lotus.Web.Resolver
  def resolve_access(nil), do: {:forbidden, "/auth/ysc"}
  def resolve_access(_user), do: :all
end
