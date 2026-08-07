defmodule Ysc.AvatarsTest do
  use Ysc.DataCase, async: true

  alias Ysc.Avatars
  alias Ysc.Accounts.User
  alias Ysc.Repo

  import Ysc.AccountsFixtures

  defmodule ServeOauthImagePlug do
    @moduledoc false
    import Plug.Conn

    @png_path Path.expand("../support/fixtures/tiny.png", __DIR__)

    def init(opts), do: opts

    def call(conn, _opts) do
      content = File.read!(@png_path)

      conn
      |> put_resp_content_type("image/png")
      |> send_resp(200, content)
    end
  end

  defmodule ServeOauthNotFoundPlug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "missing")
    end
  end

  describe "content_type_for_extension/1" do
    test "derives MIME type from allowed extensions" do
      assert Avatars.content_type_for_extension(".png") == "image/png"
      assert Avatars.content_type_for_extension(".webp") == "image/webp"
      assert Avatars.content_type_for_extension(".jpg") == "image/jpeg"
      assert Avatars.content_type_for_extension(".jpeg") == "image/jpeg"
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

  describe "sync_oauth_avatar/3 downloads over HTTP" do
    test "downloads, uploads, and creates an avatar on a successful 200 response" do
      port =
        Ysc.HttpTestServer.ensure_started(
          ServeOauthImagePlug,
          :avatars_oauth_200
        )

      user = user_fixture()
      image_url = "http://127.0.0.1:#{port}/photo.png"

      assert {:ok, avatar} = Avatars.sync_oauth_avatar(user, image_url, :google)

      assert avatar.user_id == user.id
      assert avatar.source == :google
      assert avatar.source_url == image_url
      assert avatar.processing_state == :pending
      assert is_binary(avatar.original_path)
    end

    test "skips re-download when latest avatar already matches source_url and is completed" do
      port =
        Ysc.HttpTestServer.ensure_started(
          ServeOauthImagePlug,
          :avatars_oauth_unchanged
        )

      user = user_fixture()
      image_url = "http://127.0.0.1:#{port}/photo.png"

      assert {:ok, avatar} = Avatars.sync_oauth_avatar(user, image_url, :google)

      {:ok, _} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          profile_path: "https://example.com/p.webp"
        })

      assert {:ok, :unchanged} =
               Avatars.sync_oauth_avatar(user, image_url, :google)

      assert length(Avatars.list_user_avatars(user)) == 1
    end

    test "re-downloads when the latest matching avatar hasn't finished processing" do
      port =
        Ysc.HttpTestServer.ensure_started(
          ServeOauthImagePlug,
          :avatars_oauth_pending
        )

      user = user_fixture()
      image_url = "http://127.0.0.1:#{port}/photo.png"

      assert {:ok, _pending_avatar} =
               Avatars.sync_oauth_avatar(user, image_url, :google)

      assert {:ok, %Ysc.Avatars.Avatar{}} =
               Avatars.sync_oauth_avatar(user, image_url, :google)
    end

    test "returns :download_failed for a non-200 upstream response" do
      port =
        Ysc.HttpTestServer.ensure_started(
          ServeOauthNotFoundPlug,
          :avatars_oauth_404
        )

      user = user_fixture()
      image_url = "http://127.0.0.1:#{port}/missing.png"

      assert {:error, :download_failed} =
               Avatars.sync_oauth_avatar(user, image_url, :facebook)

      assert Avatars.list_user_avatars(user) == []
    end

    test "returns :download_failed on a transport error" do
      user = user_fixture()

      assert {:error, :download_failed} =
               Avatars.sync_oauth_avatar(
                 user,
                 "http://127.0.0.1:1/unreachable",
                 :google
               )

      assert Avatars.list_user_avatars(user) == []
    end
  end

  describe "delete_avatar/2 S3 cleanup" do
    # Oban is configured `testing: :inline` (config/test.exs), so
    # AvatarCleanupWorker jobs run synchronously against real local MinIO
    # (see avatar_cleanup_worker_test.exs) instead of merely being recorded —
    # `assert_enqueued/all_enqueued` can't see them since they're immediately
    # "completed", not "available". Assert on the actual S3 side effect instead.
    test "deletes resolvable S3 objects, deduping repeats and skipping traversal attempts" do
      user = user_fixture()
      bucket = Ysc.S3Config.avatars_bucket_name()

      tiny_png =
        File.read!(Path.expand("../support/fixtures/tiny.png", __DIR__))

      original_key = "#{user.id}/a1/original.webp"
      thumb_key = "#{user.id}/a1/thumb.webp"

      bucket |> ExAws.S3.put_object(original_key, tiny_png) |> ExAws.request!()
      bucket |> ExAws.S3.put_object(thumb_key, tiny_png) |> ExAws.request!()

      assert {:ok, _} =
               bucket |> ExAws.S3.head_object(original_key) |> ExAws.request()

      assert {:ok, _} =
               bucket |> ExAws.S3.head_object(thumb_key) |> ExAws.request()

      original = "https://example.com/#{original_key}"
      thumb = "https://example.com/#{thumb_key}"
      # profile_path intentionally duplicates thumb to exercise Enum.uniq/1.
      profile = thumb

      # large_path is a path traversal attempt and must be rejected by avatar_s3_key.
      large = "https://example.com/#{user.id}/../secret.webp"

      {:ok, avatar} =
        Avatars.create_avatar(user, %{source: :upload, original_path: original})

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          thumb_path: thumb,
          profile_path: profile,
          large_path: large
        })

      assert {:ok, _deleted} = Avatars.delete_avatar(user, avatar.id)

      assert {:error, {:http_error, 404, _}} =
               bucket |> ExAws.S3.head_object(original_key) |> ExAws.request()

      assert {:error, {:http_error, 404, _}} =
               bucket |> ExAws.S3.head_object(thumb_key) |> ExAws.request()
    end

    test "enqueues no cleanup jobs when no path resolves to a valid S3 key" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          # Path is under another user's prefix, so avatar_s3_key/2 rejects it.
          original_path: "https://example.com/other-user/a1/original.webp"
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Avatars.delete_avatar(user, avatar.id)
        refute_enqueued(worker: YscWeb.Workers.AvatarCleanupWorker)
      end)
    end

    test "rejects keys containing a null byte" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/#{user.id}/a1%00/original.webp"
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Avatars.delete_avatar(user, avatar.id)
        refute_enqueued(worker: YscWeb.Workers.AvatarCleanupWorker)
      end)
    end

    test "rejects a URL with an empty path" do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com"
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Avatars.delete_avatar(user, avatar.id)
        refute_enqueued(worker: YscWeb.Workers.AvatarCleanupWorker)
      end)
    end
  end

  describe "avatar_url/2 fallback chains" do
    setup do
      user = user_fixture()

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "https://example.com/original.webp"
        })

      %{user: user, avatar: avatar}
    end

    test "thumb falls back to profile then large when missing", %{
      avatar: avatar
    } do
      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          profile_path: "https://example.com/profile.webp",
          large_path: "https://example.com/large.webp"
        })

      assert Avatars.avatar_url(avatar, :thumb) ==
               "https://example.com/profile.webp"

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{profile_path: nil})

      assert Avatars.avatar_url(avatar, :thumb) ==
               "https://example.com/large.webp"
    end

    test "profile falls back to large then thumb when missing", %{
      avatar: avatar
    } do
      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          large_path: "https://example.com/large.webp",
          thumb_path: "https://example.com/thumb.webp"
        })

      assert Avatars.avatar_url(avatar, :profile) ==
               "https://example.com/large.webp"

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{large_path: nil})

      assert Avatars.avatar_url(avatar, :profile) ==
               "https://example.com/thumb.webp"
    end

    test "large falls back to profile then thumb when missing", %{
      avatar: avatar
    } do
      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{
          processing_state: :completed,
          profile_path: "https://example.com/profile.webp",
          thumb_path: "https://example.com/thumb.webp"
        })

      assert Avatars.avatar_url(avatar, :large) ==
               "https://example.com/profile.webp"

      {:ok, avatar} =
        Avatars.update_processed_avatar(avatar, %{profile_path: nil})

      assert Avatars.avatar_url(avatar, :large) ==
               "https://example.com/thumb.webp"
    end
  end

  describe "display_avatar_url/2 default country variants" do
    test "returns Denmark defaults" do
      even_user = %User{
        id: "0190000000000000000000000",
        most_connected_country: "DK"
      }

      odd_user = %User{
        id: "0190000000000000000000001",
        most_connected_country: "DK"
      }

      assert Avatars.display_avatar_url(even_user, :profile) =~ "denmark_flag"
      assert Avatars.display_avatar_url(odd_user, :profile) =~ "denmark_houses"
    end

    test "returns Finland defaults" do
      even_user = %User{
        id: "0190000000000000000000000",
        most_connected_country: "FI"
      }

      odd_user = %User{
        id: "0190000000000000000000001",
        most_connected_country: "FI"
      }

      assert Avatars.display_avatar_url(even_user, :profile) =~ "finland_flag"
      assert Avatars.display_avatar_url(odd_user, :profile) =~ "finland_house"
    end

    test "returns Iceland defaults" do
      even_user = %User{
        id: "0190000000000000000000000",
        most_connected_country: "IS"
      }

      odd_user = %User{
        id: "0190000000000000000000001",
        most_connected_country: "IS"
      }

      assert Avatars.display_avatar_url(even_user, :profile) =~ "iceland_flag"

      assert Avatars.display_avatar_url(odd_user, :profile) =~
               "iceland_landscape"
    end

    test "defaults to SE when most_connected_country is missing entirely" do
      user = %User{id: "0190000000000000000000000"}
      assert Avatars.display_avatar_url(user, :profile) =~ "sweden_flag"
    end

    test "returns Norway defaults for both id parities" do
      even_user = %User{
        id: "0190000000000000000000000",
        most_connected_country: "NO"
      }

      odd_user = %User{
        id: "0190000000000000000000001",
        most_connected_country: "NO"
      }

      assert Avatars.display_avatar_url(even_user, :profile) =~ "norway_flag"
      assert Avatars.display_avatar_url(odd_user, :profile) =~ "norway_fjord"
    end

    test "avatar_url/1 and resolve_user_avatar_url/1 use the default :profile size" do
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

      assert Avatars.avatar_url(avatar) == "https://example.com/profile.webp"

      {:ok, user} = Avatars.set_current_avatar(user, avatar.id)
      user = Repo.preload(user, :current_avatar)

      assert Avatars.resolve_user_avatar_url(user) ==
               "https://example.com/profile.webp"
    end
  end

  describe "upload_to_s3/3" do
    test "dispatches to the configured test uploader and returns a location" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "upload_to_s3_test_#{System.unique_integer([:positive])}.txt"
        )

      File.write!(tmp_path, "hello")

      on_exit(fn -> File.rm(tmp_path) end)

      assert {:ok, location} =
               Avatars.upload_to_s3(tmp_path, "some/key.png", [])

      assert is_binary(location)
      assert location =~ "some/key.png"
    end
  end

  describe "subscribe_avatar_updates/1 and broadcast_avatar_processed/1" do
    test "delivers a broadcast to a subscribed process" do
      user = user_fixture()

      assert :ok = Avatars.subscribe_avatar_updates(user.id)
      assert :ok = Avatars.broadcast_avatar_processed(user.id)

      assert_receive {:avatar_processed, user_id}
      assert user_id == user.id
    end
  end

  describe "ci_query_explain_query/0" do
    test "returns a well-formed Ecto query for CI query-plan checks" do
      assert %Ecto.Query{} = Avatars.ci_query_explain_query()
    end
  end
end
