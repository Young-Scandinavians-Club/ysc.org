defmodule YscWeb.UserAvatar do
  @moduledoc """
  Shared logic for generating user avatar URLs.

  Uses the user's stored avatar when available, falling back to a
  country-based default image. Used by the website (CoreComponents) and
  API responses (e.g. BookingsJSON).
  """

  @doc """
  Returns the full avatar URL for a user.

  When the user has a current avatar with a stored URL, returns that URL.
  Otherwise falls back to a country-based default image.

  ## Examples

      iex> UserAvatar.url(nil, "01HXYZ123", "SE")
      "/images/default_avatars/sweden_flag.webp"
  """
  def url(avatar_url, _user_id, _country)
      when is_binary(avatar_url) and avatar_url != "" do
    avatar_url
  end

  def url(_avatar_url, user_id, country) do
    country = country || "SE"
    image_id = image_id_from_user(user_id)
    image_path = default_avatar_path(country, image_id)
    YscWeb.Endpoint.url() <> image_path
  end

  defp image_id_from_user(nil), do: 0
  defp image_id_from_user(user_id) when is_integer(user_id), do: rem(user_id, 2)

  defp image_id_from_user(user_id) when is_binary(user_id) do
    digits =
      user_id
      |> String.replace(~r/[^\d]/, "")

    if digits == "" do
      0
    else
      String.to_integer(digits) |> rem(2)
    end
  end

  defp default_avatar_path("DK", 0),
    do: "/images/default_avatars/denmark_flag.webp"

  defp default_avatar_path("DK", 1),
    do: "/images/default_avatars/denmark_houses.webp"

  defp default_avatar_path("FI", 0),
    do: "/images/default_avatars/finland_flag.webp"

  defp default_avatar_path("FI", 1),
    do: "/images/default_avatars/finland_house.webp"

  defp default_avatar_path("IS", 0),
    do: "/images/default_avatars/iceland_flag.webp"

  defp default_avatar_path("IS", 1),
    do: "/images/default_avatars/iceland_landscape.webp"

  defp default_avatar_path("NO", 0),
    do: "/images/default_avatars/norway_flag.webp"

  defp default_avatar_path("NO", 1),
    do: "/images/default_avatars/norway_fjord.webp"

  defp default_avatar_path("SE", 0),
    do: "/images/default_avatars/sweden_flag.webp"

  defp default_avatar_path("SE", 1),
    do: "/images/default_avatars/sweden_houses.webp"

  defp default_avatar_path(_, image_id), do: default_avatar_path("SE", image_id)
end
