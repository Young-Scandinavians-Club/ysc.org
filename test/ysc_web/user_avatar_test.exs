defmodule YscWeb.UserAvatarTest do
  @moduledoc """
  Tests for UserAvatar URL generation (stored avatar URL + country-based defaults).
  """
  use ExUnit.Case, async: true

  alias YscWeb.UserAvatar

  describe "url/3" do
    test "returns stored avatar URL when provided" do
      url = UserAvatar.url("https://example.com/avatar.webp", "01HXYZ123", "SE")
      assert url == "https://example.com/avatar.webp"
    end

    test "returns default URL when avatar_url is nil" do
      url = UserAvatar.url(nil, "01HXYZ123", "NO")

      assert String.starts_with?(url, "http")
      assert url =~ "/images/default_avatars/"
      assert url =~ "norway"
    end

    test "returns default URL when avatar_url is empty string" do
      url = UserAvatar.url("", "01HXYZ123", "SE")

      assert String.starts_with?(url, "http")
      assert url =~ "/images/default_avatars/"
      assert url =~ "sweden"
    end

    test "uses country-specific defaults" do
      assert UserAvatar.url(nil, "0", "DK") =~ "denmark"
      assert UserAvatar.url(nil, "1", "FI") =~ "finland"
      assert UserAvatar.url(nil, "0", "IS") =~ "iceland"
      assert UserAvatar.url(nil, "1", "NO") =~ "norway"
      assert UserAvatar.url(nil, "0", "SE") =~ "sweden"
    end

    test "falls back to Sweden default for unknown country" do
      url = UserAvatar.url(nil, "01HXYZ", "XX")
      assert url =~ "sweden"
    end

    test "uses most_connected_country nil as SE" do
      url = UserAvatar.url(nil, "0", nil)
      assert url =~ "sweden"
    end

    test "image_id varies by user_id for default avatar selection" do
      url_even = UserAvatar.url(nil, "01HXYZ000", "SE")
      url_odd = UserAvatar.url(nil, "01HXYZ001", "SE")

      assert url_even =~ "sweden_flag"
      assert url_odd =~ "sweden_houses"
    end
  end
end
