defmodule YscWeb.UserAvatarTest do
  @moduledoc """
  Tests for UserAvatar URL generation (Gravatar + country-based defaults).
  """
  use ExUnit.Case, async: true

  alias YscWeb.UserAvatar

  describe "url/3" do
    test "returns Gravatar URL when email is provided" do
      url = UserAvatar.url("test@example.com", "01HXYZ123", "SE")

      assert String.starts_with?(url, "https://")
      assert url =~ "gravatar.com"
      assert url =~ "avatar/"
      assert url =~ "s=512"
      assert url =~ "d="
    end

    test "returns default URL when email is nil" do
      url = UserAvatar.url(nil, "01HXYZ123", "NO")

      assert String.starts_with?(url, "http")
      assert url =~ "/images/default_avatars/"
      assert url =~ "norway"
    end

    test "returns default URL when email is empty string" do
      url = UserAvatar.url("", "01HXYZ123", "SE")

      assert String.starts_with?(url, "http")
      assert url =~ "/images/default_avatars/"
      assert url =~ "sweden"
    end

    test "uses country-specific default when no Gravatar" do
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

    test "normalizes email (lowercase, trimmed) for Gravatar" do
      url1 = UserAvatar.url("Test@Example.COM", "0", "SE")
      url2 = UserAvatar.url("test@example.com", "0", "SE")

      assert url1 == url2
    end

    test "image_id varies by user_id for default avatar selection" do
      url_even = UserAvatar.url(nil, "01HXYZ000", "SE")
      url_odd = UserAvatar.url(nil, "01HXYZ001", "SE")

      # Different image_id (0 vs 1) should yield different default paths
      assert url_even =~ "sweden_flag"
      assert url_odd =~ "sweden_houses"
    end
  end
end
