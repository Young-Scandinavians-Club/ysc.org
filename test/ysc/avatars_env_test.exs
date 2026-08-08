defmodule Ysc.AvatarsEnvTest do
  # async: false — mutates the process-global `:ysc, :environment` config via
  # Ysc.Test.EnvHelper. Split out from Ysc.AvatarsTest (which is async: true)
  # so this doesn't race with other async suites doing the same (see the
  # geo_ip_test.exs "returns true in sandbox" CI flake for the failure mode).
  use Ysc.DataCase, async: false

  alias Ysc.Avatars

  import Ysc.AccountsFixtures

  describe "sync_oauth_avatar/3" do
    test "rejects loopback URLs in prod environment without creating an avatar" do
      Ysc.Test.EnvHelper.with_environment("prod", fn ->
        user = user_fixture()

        assert {:error, :download_failed} =
                 Avatars.sync_oauth_avatar(
                   user,
                   "http://127.0.0.1:9/avatar.jpg",
                   :facebook
                 )

        assert Avatars.list_user_avatars(user) == []
      end)
    end
  end
end
