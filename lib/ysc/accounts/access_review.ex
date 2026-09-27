defmodule Ysc.Accounts.AccessReview do
  @moduledoc """
  Lists accounts with elevated access (admin and volunteer roles) for the
  annual access review sent to the WebTech team.

  Deleted accounts are excluded since they can no longer sign in.
  """

  import Ecto.Query, warn: false

  alias Ysc.Accounts.{AuthEvent, User}
  alias Ysc.Repo

  @privileged_roles [:admin, :volunteer]

  @doc """
  Returns every non-deleted admin and volunteer, ordered by role then name,
  with the time of their most recent successful sign-in (or `nil`).
  """
  def list_privileged_users do
    Repo.all(privileged_users_query())
  end

  @doc false
  def privileged_users_query do
    last_sign_in =
      from(ae in AuthEvent,
        where: ae.user_id == parent_as(:user).id,
        where: ae.event_type == "login_success",
        where: ae.success == true,
        order_by: [desc: ae.inserted_at],
        limit: 1,
        select: %{inserted_at: ae.inserted_at}
      )

    from(u in User,
      as: :user,
      left_lateral_join: ls in subquery(last_sign_in),
      on: true,
      where: u.role in ^@privileged_roles,
      where: u.state != :deleted,
      order_by: [asc: u.role, asc: u.last_name, asc: u.first_name],
      select: %{
        id: u.id,
        first_name: u.first_name,
        last_name: u.last_name,
        email: u.email,
        role: u.role,
        state: u.state,
        board_position: u.board_position,
        last_sign_in_at: ls.inserted_at
      }
    )
  end

  @doc false
  def ci_query_explain_query, do: privileged_users_query()
end
