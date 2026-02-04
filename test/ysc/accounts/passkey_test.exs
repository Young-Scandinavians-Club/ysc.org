defmodule Ysc.Accounts.PasskeyTest do
  @moduledoc """
  Tests for passkey-related functions in Accounts context.
  """
  use Ysc.DataCase

  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.{User, UserPasskey}

  describe "passkey management" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.mark_email_verified(user)
      %{user: user}
    end

    test "create_user_passkey/2 creates a passkey with valid data", %{
      user: user
    } do
      credential_id = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      attrs = %{
        external_id: credential_id,
        public_key: UserPasskey.encode_public_key(public_key_map),
        nickname: "Test Device"
      }

      assert {:ok, passkey} = Accounts.create_user_passkey(user, attrs)
      assert passkey.user_id == user.id
      assert passkey.external_id == credential_id
      assert passkey.nickname == "Test Device"
      assert passkey.sign_count == 0
      assert is_nil(passkey.last_used_at)

      # Verify public key can be decoded
      decoded_key = UserPasskey.decode_public_key(passkey.public_key)
      assert decoded_key == public_key_map
    end

    test "create_user_passkey/2 requires external_id", %{user: user} do
      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      attrs = %{
        public_key: UserPasskey.encode_public_key(public_key_map),
        nickname: "Test Device"
      }

      assert {:error, changeset} = Accounts.create_user_passkey(user, attrs)
      assert %{external_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "create_user_passkey/2 requires public_key", %{user: user} do
      credential_id = :crypto.strong_rand_bytes(16)

      attrs = %{
        external_id: credential_id,
        nickname: "Test Device"
      }

      assert {:error, changeset} = Accounts.create_user_passkey(user, attrs)
      assert %{public_key: ["can't be blank"]} = errors_on(changeset)
    end

    test "get_user_passkeys/1 returns all passkeys for a user", %{user: user} do
      # Create multiple passkeys
      credential_id1 = :crypto.strong_rand_bytes(16)
      credential_id2 = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      {:ok, _passkey1} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id1,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "Device 1"
        })

      {:ok, _passkey2} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id2,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "Device 2"
        })

      passkeys = Accounts.get_user_passkeys(user)
      assert length(passkeys) == 2
      assert Enum.all?(passkeys, &(&1.user_id == user.id))
    end

    test "get_user_passkey_by_external_id/1 finds passkey by credential ID", %{
      user: user
    } do
      credential_id = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      {:ok, created_passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "Test Device"
        })

      found_passkey = Accounts.get_user_passkey_by_external_id(credential_id)
      assert found_passkey != nil
      assert found_passkey.id == created_passkey.id
      assert found_passkey.external_id == credential_id
    end

    test "get_user_passkey_by_external_id/1 returns nil for non-existent credential",
         %{
           user: _user
         } do
      non_existent_id = :crypto.strong_rand_bytes(16)
      assert Accounts.get_user_passkey_by_external_id(non_existent_id) == nil
    end

    test "update_passkey_sign_count/2 updates sign_count and last_used_at", %{
      user: user
    } do
      credential_id = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      {:ok, passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "Test Device",
          sign_count: 0
        })

      assert passkey.sign_count == 0
      assert is_nil(passkey.last_used_at)

      new_sign_count = 5

      assert {:ok, updated_passkey} =
               Accounts.update_passkey_sign_count(passkey, new_sign_count)

      assert updated_passkey.sign_count == new_sign_count
      assert updated_passkey.last_used_at != nil

      # Reload from database to verify
      reloaded = Accounts.get_user_passkey_by_external_id(credential_id)
      assert reloaded.sign_count == new_sign_count
      assert reloaded.last_used_at != nil
    end

    test "update_passkey_sign_count/2 handles sign_count decrease (replay attack)",
         %{user: user} do
      credential_id = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      {:ok, passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "Test Device",
          sign_count: 10
        })

      # Try to update with lower sign_count (should still work, but indicates replay)
      # The validation happens in the LiveView, not here
      assert {:ok, updated_passkey} =
               Accounts.update_passkey_sign_count(passkey, 5)

      assert updated_passkey.sign_count == 5
    end
  end

  describe "should_show_passkey_prompt?/1" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.mark_email_verified(user)
      %{user: user}
    end

    test "returns true when user has no passkeys and never dismissed", %{
      user: user
    } do
      assert Accounts.should_show_passkey_prompt?(user) == true
    end

    test "returns false when user has passkeys", %{user: user} do
      credential_id = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      {:ok, _passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "Test Device"
        })

      assert Accounts.should_show_passkey_prompt?(user) == false
    end

    test "returns false when user dismissed less than 30 days ago", %{
      user: user
    } do
      dismissed_at = DateTime.add(DateTime.utc_now(), -15, :day)

      updated_user =
        user
        |> User.update_user_changeset(%{
          passkey_prompt_dismissed_at: dismissed_at
        })
        |> Ysc.Repo.update!()

      # Reload to get fresh data
      reloaded_user = Ysc.Repo.reload!(updated_user)
      assert Accounts.should_show_passkey_prompt?(reloaded_user) == false
    end

    test "returns true when user dismissed more than 30 days ago", %{user: user} do
      dismissed_at = DateTime.add(DateTime.utc_now(), -31, :day)

      updated_user =
        user
        |> User.update_user_changeset(%{
          passkey_prompt_dismissed_at: dismissed_at
        })
        |> Ysc.Repo.update!()

      # Reload to get fresh data
      reloaded_user = Ysc.Repo.reload!(updated_user)
      assert Accounts.should_show_passkey_prompt?(reloaded_user) == true
    end
  end

  describe "dismiss_passkey_prompt/1" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.mark_email_verified(user)
      %{user: user}
    end

    test "sets passkey_prompt_dismissed_at to current time", %{user: user} do
      assert is_nil(user.passkey_prompt_dismissed_at)

      assert {:ok, updated_user} = Accounts.dismiss_passkey_prompt(user)
      assert updated_user.passkey_prompt_dismissed_at != nil

      assert DateTime.diff(
               DateTime.utc_now(),
               updated_user.passkey_prompt_dismissed_at,
               :second
             ) <
               5
    end

    test "updates existing dismissal timestamp", %{user: user} do
      old_dismissed_at = DateTime.add(DateTime.utc_now(), -10, :day)

      updated_user =
        user
        |> User.update_user_changeset(%{
          passkey_prompt_dismissed_at: old_dismissed_at
        })
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      assert {:ok, newly_updated_user} =
               Accounts.dismiss_passkey_prompt(updated_user)

      assert newly_updated_user.passkey_prompt_dismissed_at != old_dismissed_at

      assert DateTime.compare(
               newly_updated_user.passkey_prompt_dismissed_at,
               old_dismissed_at
             ) ==
               :gt
    end
  end
end
