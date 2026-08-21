defmodule YscWeb.Api.AppAuthJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's auth endpoints.
  """

  def session(%{token: token, user: user}) do
    %{
      token: token,
      user: %{
        id: to_string(user.id),
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        role: user.role
      }
    }
  end
end
