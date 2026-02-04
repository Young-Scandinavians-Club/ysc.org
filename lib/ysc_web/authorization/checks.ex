defmodule YscWeb.Authorization.Policy.Checks do
  @moduledoc """
  Authorization policy check functions.

  Provides helper functions for checking authorization policies, such as
  resource ownership and role-based access.
  """
  alias Ysc.Accounts.User

  def own_resource(%User{id: id}, %{user_id: id}) when is_binary(id), do: true

  def own_resource(%User{id: id}, %{primary_user_id: id}) when is_binary(id),
    do: true

  def own_resource(%User{id: id}, %{primary_user_id: primary_user_id})
      when is_binary(id) and is_binary(primary_user_id),
      do: id == primary_user_id

  def own_resource(_, _), do: false

  def own_resource(%User{id: id}, %{user_id: id}, _opts) when is_binary(id),
    do: true

  def own_resource(%User{id: id}, %{primary_user_id: id}, _opts)
      when is_binary(id), do: true

  def own_resource(%User{id: id}, %{primary_user_id: primary_user_id}, _opts)
      when is_binary(id) and is_binary(primary_user_id),
      do: id == primary_user_id

  def own_resource(_, _, _), do: false

  def role(%User{role: role}, _object, role), do: true
  def role(_, _, _), do: false

  def can_send_family_invite(%User{} = user, _object) do
    Ysc.Accounts.can_send_family_invite?(user)
  end

  def can_send_family_invite(_, _), do: false
end
