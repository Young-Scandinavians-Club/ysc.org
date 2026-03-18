defmodule YscWeb.UserAvatar do
  @moduledoc """
  Shared logic for generating user avatar URLs (Gravatar with country-based defaults).

  Used by the website (CoreComponents) and API responses (e.g. BookingsJSON).
  """

  import Exgravatar

  @doc """
  Returns the full avatar URL for a user.

  Uses Gravatar when available, falling back to a country-based default image
  (same as the website). Suitable for API responses where the client needs
  a loadable image URL.

  ## Examples

      iex> UserAvatar.url("user@example.com", "01HXYZ123", "SE")
      "https://secure.gravatar.com/avatar/..."

      iex> UserAvatar.url(nil, "01HXYZ123", "NO")
      "https://ysc.org/images/default_avatars/norway_flag.webp"
  """
  def url(email, user_id, country) do
    country = country || "SE"
    image_id = image_id_from_user(user_id)
    image_path = default_avatar_path(country, image_id)
    default_url = YscWeb.Endpoint.url() <> image_path

    cleaned_email =
      (email || "")
      |> String.downcase()
      |> String.trim()

    if cleaned_email == "" do
      default_url
    else
      gravatar_url(cleaned_email, s: 512, d: default_url)
    end
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
