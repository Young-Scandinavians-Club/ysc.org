defmodule YscWeb.Authorization do
  @moduledoc """
  Call-site API for `YscWeb.Authorization.Policy`.

  Every "who may do this" question in contexts, LiveViews and controllers goes
  through here so the rules live in one place (the policy).

    * `can?/3` - boolean, for showing or hiding UI and for guards.
    * `authorize/3` - `:ok | {:error, :unauthorized}`, for contexts and
      handlers that must refuse.

  The subject can be:

    * a `%User{}` - the usual case, and the only one that supports ownership
      rules (`:own_resource`);
    * a role atom (`:admin`, `:volunteer`, `:member`) - for components that
      only carry `admin_role`. Role atoms match role rules only, never
      ownership, so use them for staff-versus-admin questions;
    * `:system` - trusted internal callers (Oban workers, scripts). Only
      `authorize/3` accepts it, and it must be passed explicitly;
    * anything else, including `nil` - denied.
  """
  alias Ysc.Accounts.User
  alias YscWeb.Authorization.Policy

  @roles [:admin, :volunteer, :member]

  @spec can?(User.t() | atom() | nil, atom(), term()) :: boolean()
  def can?(subject, action, object \\ nil)

  def can?(%User{} = user, action, object) when is_atom(action),
    do: Policy.authorize?(action, user, object)

  def can?(role, action, object) when role in @roles and is_atom(action),
    do: can?(%User{role: role}, action, object)

  def can?(_subject, _action, _object), do: false

  @doc "The negation of `can?/3`, for guard clauses that refuse."
  @spec cannot?(User.t() | atom() | nil, atom(), term()) :: boolean()
  def cannot?(subject, action, object \\ nil),
    do: not can?(subject, action, object)

  @spec authorize(User.t() | atom() | nil, atom(), term()) ::
          :ok | {:error, :unauthorized}
  def authorize(subject, action, object \\ nil)

  def authorize(:system, _action, _object), do: :ok

  def authorize(subject, action, object) do
    if can?(subject, action, object), do: :ok, else: {:error, :unauthorized}
  end
end
