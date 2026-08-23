defmodule YscWeb.Api.AppMembersJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's member search endpoint.
  """

  alias Ysc.Accounts
  alias YscWeb.UserAvatar

  def search(%{users: users}) do
    %{data: Enum.map(users, &member/1)}
  end

  defp member(u) do
    %{
      id: to_string(u.id),
      first_name: u.first_name,
      last_name: u.last_name,
      email: u.email,
      has_active_membership: Accounts.has_active_membership?(u),
      avatar_url:
        UserAvatar.url(
          Ysc.Avatars.resolve_user_avatar_url(u, :thumb),
          u.id,
          u.most_connected_country
        )
    }
  end
end
