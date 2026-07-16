defmodule Ysc.Accounts.UserProfileCacheTest do
  use Ysc.DataCase, async: false

  @moduletag process_caches: true

  alias Ysc.Accounts
  alias Ysc.Accounts.UserProfileCache

  import Ysc.AccountsFixtures

  setup do
    Cachex.clear(:ysc_cache)
    :ok
  end

  test "get_user! caches user profile" do
    user = user_fixture()

    user1 = UserProfileCache.get_user!(user.id, [])
    user2 = UserProfileCache.get_user!(user.id, [])

    assert user1.id == user2.id
    assert user1.email == user2.email
  end

  test "invalidate_user refetches after profile update" do
    user = user_fixture()

    UserProfileCache.get_user!(user.id, [])

    {:ok, updated} =
      Accounts.update_user_profile(user, %{first_name: "CachedFirst"})

    UserProfileCache.invalidate_user(user.id)

    reloaded = UserProfileCache.get_user!(user.id, [])
    assert reloaded.first_name == updated.first_name
  end

  test "create_user_passkey invalidates cached profile preloads" do
    user = user_fixture()

    cached = UserProfileCache.get_user!(user.id, [:passkeys])
    assert cached.passkeys == []

    passkey_fixture(user)

    refreshed = UserProfileCache.get_user!(user.id, [:passkeys])
    assert length(refreshed.passkeys) == 1
  end

  test "delete_user_passkey invalidates cached profile preloads" do
    user = user_fixture()
    passkey_fixture(user)

    cached = UserProfileCache.get_user!(user.id, [:passkeys])
    assert length(cached.passkeys) == 1

    [passkey] = Accounts.get_user_passkeys(user)
    assert {:ok, _} = Accounts.delete_user_passkey(passkey)

    refreshed = UserProfileCache.get_user!(user.id, [:passkeys])
    assert refreshed.passkeys == []
  end

  test "get_user_by_session_token does not depend on UserProfileCache" do
    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    UserProfileCache.get_user!(user.id, [])

    session_user = Accounts.get_user_by_session_token(token)
    assert session_user.id == user.id
  end
end
