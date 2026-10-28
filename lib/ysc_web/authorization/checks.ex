defmodule YscWeb.Authorization.Policy.Checks do
  @moduledoc """
  Authorization policy check functions.

  Provides helper functions for checking authorization policies, such as
  resource ownership and role-based access.

  Ownership (`own_resource`) matches when the object is:

    * the subject themself (a `%User{}` with the same `id`) - lets a member
      read their own user record,
    * owned through `user_id`,
    * a sub-account owned through `primary_user_id`, or
    * created by the subject through `created_by_id` (e.g. scan sessions).

  Child records with no owner column of their own (ticket details, expense
  report items, booking guests, merch order items, ...) never match; callers
  authorizing those pass the parent's owner as the object, for example
  `%{user_id: report.user_id}`.
  """
  alias Ysc.Accounts.User

  def own_resource(%User{id: id}, %User{id: id}) when is_binary(id), do: true

  def own_resource(%User{id: id}, %{user_id: id}) when is_binary(id), do: true

  def own_resource(%User{id: id}, %{primary_user_id: id}) when is_binary(id),
    do: true

  def own_resource(%User{id: id}, %{primary_user_id: primary_user_id})
      when is_binary(id) and is_binary(primary_user_id),
      do: id == primary_user_id

  def own_resource(%User{id: id}, %{created_by_id: id}) when is_binary(id),
    do: true

  def own_resource(_, _), do: false

  def own_resource(user, object, _opts), do: own_resource(user, object)

  @doc """
  Any signed-in user, regardless of role. Use for actions that need an
  account but no particular privilege (placing an order, posting a comment).
  Unlike `allow true`, this rejects anonymous callers (`nil` subject).
  """
  def authenticated(%User{}, _object), do: true
  def authenticated(_, _), do: false

  def authenticated(user, object, _opts), do: authenticated(user, object)

  def role(%User{role: role}, _object, role), do: true
  def role(_, _, _), do: false

  def can_send_family_invite(%User{} = user, _object) do
    Ysc.Accounts.can_send_family_invite?(user)
  end

  def can_send_family_invite(_, _), do: false
end
