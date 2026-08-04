defmodule Ysc.AvatarsTest do
  use Ysc.DataCase, async: true

  alias Ysc.Avatars
  alias Ysc.Accounts.User
  alias Ysc.Repo

  import Ysc.AccountsFixtures

  describe "content_type_for_extension/1" do
    test "derives MIME type from allowed extensions" do
      assert Avatars.content_type_for_extension(".png") == "image/png"
      assert Avatars.content_type_for_extension(".webp") == "image/webp"
      assert Avatars.content_type_for_extension(".jpg") == "image/jpeg"
      assert Avatars.content_type_for_extension(".gif") == "image/gif"
      assert Avatars.content_type_for_extension(".unknown") == "image/jpeg"
    end
  end

  describe "create_avatar_and_enqueue_job/2" do
    test "creates avatar and enqueues processor job in one transaction" do
      user = user_fixture()

      assert {:ok, avatar} =
               Avatars.create_avatar_and_enqueue_job(user, %{
                 source: :upload,
                 original_path: "https://example.com/avatars/original.webp"
               })

      assert avatar.user_id == user.id
      assert avatar.processing_state == :pending
      assert Avatars.get_avatar!(avatar.id).id == avatar.id
    end

    test "returns error without creating avatar when attrs are invalid" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Avatars.create_avatar_and_enqueue_job(user, %{})

      refute_enqueued(worker: YscWeb.Workers.AvatarProcessor)
    end

    test "returns error when the user no longer exists" do
      user = user_fixture()
      user_id = user.id
      Repo.delete!(user)

      assert {:error, %Ecto.Changeset{}} =
               Avatars.create_avatar_and_enqueue_job(%User{id: user_id}, %{
                 source: :upload,
                 original_path: "https://example.com/avatars/original.webp"
               })

      refute_enqueued(worker: YscWeb.Workers.AvatarProcessor)
    end
  end

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

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          thumb_path: "https://example.com/thumb.webp",
          profile_path: "https://example.com/profile.webp",
          large_path: "https://example.com/large.webp"
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

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          thumb_path: "https://example.com/thumb.webp",
          profile_path: "https://example.com/profile.webp",
          large_path: "https://example.com/large.webp"
        })

      assert {:error, :not_found} = Avatars.set_current_avatar(user2, avatar.id)
    end

    test "rejects non-completed avatars" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/test.webp"
        })

      assert {:error, :not_found} = Avatars.set_current_avatar(user, avatar.id)
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

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          thumb_path: "https://example.com/thumb.webp",
          profile_path: "https://example.com/profile.webp",
          large_path: "https://example.com/large.webp"
        })

      {:ok, user_with_avatar} = Avatars.set_current_avatar(user, avatar.id)
      assert user_with_avatar.current_avatar_id == avatar.id

      {:ok, cleared_user} = Avatars.clear_current_avatar(user_with_avatar)
      assert is_nil(cleared_user.current_avatar_id)
    end
  end

  describe "delete_avatar/2" do
    test "deletes an avatar owned by the user" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path:
            "https://example.com/avatars/#{user.id}/a1/original.webp"
        })

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          thumb_path: "https://example.com/avatars/#{user.id}/a1/thumb.webp",
          profile_path:
            "https://example.com/avatars/#{user.id}/a1/profile.webp",
          large_path: "https://example.com/avatars/#{user.id}/a1/large.webp"
        })

      assert {:ok, deleted} = Avatars.delete_avatar(user, avatar.id)
      assert deleted.id == avatar.id
      assert is_nil(Avatars.get_avatar(avatar.id))
    end

    test "clears the user's current_avatar_id when deleting the current avatar" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path:
            "https://example.com/avatars/#{user.id}/a1/original.webp"
        })

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          profile_path: "https://example.com/avatars/#{user.id}/a1/profile.webp"
        })

      {:ok, user} = Avatars.set_current_avatar(user, avatar.id)
      assert user.current_avatar_id == avatar.id

      assert {:ok, _} = Avatars.delete_avatar(user, avatar.id)

      reloaded = Repo.get!(User, user.id)
      assert is_nil(reloaded.current_avatar_id)
    end

    test "rejects deleting another user's avatar" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user1, %{
          source: :upload,
          original_path:
            "https://example.com/avatars/#{user1.id}/a1/original.webp"
        })

      assert {:error, :not_found} = Avatars.delete_avatar(user2, avatar.id)
      assert Avatars.get_avatar(avatar.id)
    end

    test "returns error for unknown avatar id" do
      user = user_fixture()

      assert {:error, :not_found} =
               Avatars.delete_avatar(user, Ecto.ULID.generate())
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

  describe "resolve_user_avatar_url/2" do
    test "returns profile URL when current_avatar is preloaded and completed" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/original.webp"
        })

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          profile_path: "https://example.com/profile.webp",
          thumb_path: "https://example.com/thumb.webp"
        })

      {:ok, user} = Avatars.set_current_avatar(user, avatar.id)
      user = Ysc.Repo.preload(user, :current_avatar)

      assert Avatars.resolve_user_avatar_url(user, :profile) ==
               "https://example.com/profile.webp"

      assert Avatars.resolve_user_avatar_url(user, :thumb) ==
               "https://example.com/thumb.webp"
    end

    test "returns nil when current_avatar is not preloaded" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/original.webp"
        })

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          profile_path: "https://example.com/profile.webp"
        })

      {:ok, user} = Avatars.set_current_avatar(user, avatar.id)

      refute Ecto.assoc_loaded?(user.current_avatar)
      assert is_nil(Avatars.resolve_user_avatar_url(user, :profile))
    end

    test "returns nil when current avatar is still processing" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/original.webp"
        })

      {:ok, user} =
        user
        |> Ecto.Changeset.change(current_avatar_id: avatar.id)
        |> Ysc.Repo.update()

      user = Ysc.Repo.preload(user, :current_avatar)

      assert is_nil(Avatars.resolve_user_avatar_url(user, :profile))
      refute avatar.processing_state == :completed
    end

    test "returns nil for non-user input" do
      assert is_nil(Avatars.resolve_user_avatar_url(nil, :profile))
    end
  end

  describe "display_avatar_url/2" do
    test "returns uploaded avatar URL when preloaded and completed" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/original.webp"
        })

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          profile_path: "https://example.com/display.webp"
        })

      {:ok, user} = Avatars.set_current_avatar(user, avatar.id)
      user = Ysc.Repo.preload(user, :current_avatar)

      assert Avatars.display_avatar_url(user, :profile) ==
               "https://example.com/display.webp"
    end

    test "returns country default path when no uploaded avatar is available" do
      user = user_fixture(%{most_connected_country: "NO"})

      assert Avatars.display_avatar_url(user, :profile) =~
               "/images/default_avatars/norway"
    end

    test "uses Sweden defaults for unknown country codes" do
      user = user_fixture(%{most_connected_country: "XX"})

      url = Avatars.display_avatar_url(user, :thumb)
      assert url =~ "/images/default_avatars/sweden"
    end

    test "alternates default image variant based on user id digits" do
      even_user = %User{
        id: "0190000000000000000000000",
        most_connected_country: "SE"
      }

      odd_user = %User{
        id: "0190000000000000000000001",
        most_connected_country: "SE"
      }

      assert Avatars.display_avatar_url(even_user, :profile) =~ "sweden_flag"
      assert Avatars.display_avatar_url(odd_user, :profile) =~ "sweden_houses"
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

    test "rejects non-http(s) URLs via UrlFetchGuard without creating an avatar" do
      user = user_fixture()

      assert {:error, :download_failed} =
               Avatars.sync_oauth_avatar(user, "file:///etc/passwd", :google)

      assert Avatars.list_user_avatars(user) == []
    end

  end
end
