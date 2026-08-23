defmodule YscWeb.Api.AppAuthJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's auth endpoints.
  """

  alias YscWeb.UserAvatar

  def session(%{token: token, user: user}) do
    %{
      token: token,
      user: %{
        id: to_string(user.id),
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        role: user.role,
        avatar_url:
          UserAvatar.url(
            Ysc.Avatars.resolve_user_avatar_url(user, :thumb),
            user.id,
            user.most_connected_country
          )
      }
    }
  end
end
