defmodule YscWeb.Api.AppMembersJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's member search endpoint.
  """

  alias Ysc.Accounts.MembershipCache
  alias YscWeb.UserAvatar

  def search(%{users: users}) do
    memberships = MembershipCache.batch_membership_data_for_users(users)
    %{data: Enum.map(users, &member(&1, memberships))}
  end

  defp member(u, memberships) do
    {membership, _plan_type} = Map.get(memberships, u.id, {nil, nil})

    %{
      id: to_string(u.id),
      first_name: u.first_name,
      last_name: u.last_name,
      email: u.email,
      has_active_membership: not is_nil(membership),
      avatar_url:
        UserAvatar.url(
          Ysc.Avatars.resolve_user_avatar_url(u, :thumb),
          u.id,
          u.most_connected_country
        )
    }
  end
end
