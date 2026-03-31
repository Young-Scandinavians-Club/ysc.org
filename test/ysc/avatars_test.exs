defmodule Ysc.AvatarsTest do
  use Ysc.DataCase, async: true

  alias Ysc.Avatars

  import Ysc.AccountsFixtures

  describe "create_avatar/2" do
    test "creates an avatar record for a user" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/avatars/original.webp"
        })

      assert avatar.user_id == user.id
      assert avatar.source == :upload
      assert avatar.original_path == "https://example.com/avatars/original.webp"
      assert avatar.processing_state == :pending
    end

    test "requires source and original_path" do
      user = user_fixture()

      assert {:error, changeset} = Avatars.create_avatar(user, %{})
      assert "can't be blank" in errors_on(changeset).source
      assert "can't be blank" in errors_on(changeset).original_path
    end

    test "validates source values" do
      user = user_fixture()

      assert {:error, changeset} =
               Avatars.create_avatar(user, %{
                 source: :invalid,
                 original_path: "https://example.com/test.jpg"
               })

      assert errors_on(changeset).source != []
    end
  end

  describe "list_user_avatars/1" do
    test "returns completed avatars for a user, most recent first" do
      user = user_fixture()

      {:ok, avatar1} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/1.webp"
        })

      {:ok, _avatar2_pending} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/2.webp"
        })

      {:ok, avatar3} =
        Avatars.create_avatar(user, %{
          source: :google,
          original_path: "https://example.com/3.webp"
        })

      Avatars.update_processed_avatar(avatar1, %{
        processing_state: :completed,
        profile_path: "p1"
      })

      Avatars.update_processed_avatar(avatar3, %{
        processing_state: :completed,
        profile_path: "p3"
      })

      avatars = Avatars.list_user_avatars(user)
      assert length(avatars) == 2
      assert Enum.at(avatars, 0).id == avatar3.id
      assert Enum.at(avatars, 1).id == avatar1.id
    end

    test "returns empty list for user with no avatars" do
      user = user_fixture()
      assert Avatars.list_user_avatars(user) == []
    end
  end

  describe "set_current_avatar/2" do
    test "sets the current avatar for a user" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/test.webp"
        })

      {:ok, updated_user} = Avatars.set_current_avatar(user, avatar.id)
      assert updated_user.current_avatar_id == avatar.id
    end

    test "rejects setting another user's avatar" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user1, %{
          source: :upload,
          original_path: "https://example.com/test.webp"
        })

      assert {:error, :not_owner} = Avatars.set_current_avatar(user2, avatar.id)
    end
  end

  describe "clear_current_avatar/1" do
    test "clears the current avatar" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/test.webp"
        })

      {:ok, user_with_avatar} = Avatars.set_current_avatar(user, avatar.id)
      assert user_with_avatar.current_avatar_id == avatar.id

      {:ok, cleared_user} = Avatars.clear_current_avatar(user_with_avatar)
      assert is_nil(cleared_user.current_avatar_id)
    end
  end

  describe "avatar_url/2" do
    test "returns profile_path for completed avatar" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/test.webp"
        })

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          thumb_path: "https://example.com/thumb.webp",
          profile_path: "https://example.com/profile.webp",
          large_path: "https://example.com/large.webp"
        })

      assert Avatars.avatar_url(avatar, :profile) ==
               "https://example.com/profile.webp"

      assert Avatars.avatar_url(avatar, :thumb) ==
               "https://example.com/thumb.webp"

      assert Avatars.avatar_url(avatar, :large) ==
               "https://example.com/large.webp"
    end

    test "returns nil for non-completed avatar" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/test.webp"
        })

      assert is_nil(Avatars.avatar_url(avatar, :profile))
    end

    test "returns nil for nil avatar" do
      assert is_nil(Avatars.avatar_url(nil, :profile))
    end
  end

  describe "sync_oauth_avatar/3" do
    test "returns :no_image for nil image_url" do
      user = user_fixture()
      assert {:ok, :no_image} = Avatars.sync_oauth_avatar(user, nil, :google)
    end

    test "returns :no_image for empty image_url" do
      user = user_fixture()
      assert {:ok, :no_image} = Avatars.sync_oauth_avatar(user, "", :google)
    end
  end
end
