defmodule YscWeb.Workers.AvatarProcessorTest do
  @moduledoc """
  Tests for AvatarProcessor Oban worker.

  Uses real local MinIO (see `config/test.exs` / CI's "Start MinIO and create
  buckets" step) for the raw-image download, since AvatarProcessor now
  downloads via a plain unsigned HTTP GET against the object's public URL
  (not a signed ExAws GetObject — see `download_original_from_s3!/2`'s
  moduledoc for why). Re-uploads (stripped original + thumbnails) go through
  `Ysc.Avatars.TestS3Uploader` in test (see `:avatars_s3_uploader` in
  config/test.exs) and don't touch S3 at all, so they're untouched by this.
  """

  use Ysc.DataCase, async: false

  alias Ysc.Avatars
  alias Ysc.Repo
  alias Ysc.S3Config
  alias YscWeb.Workers.AvatarProcessor

  import Ysc.AccountsFixtures

  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )

  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------

  defp make_oban_job(avatar_id) do
    %Oban.Job{
      id: 1,
      args: %{"id" => avatar_id},
      worker: "YscWeb.Workers.AvatarProcessor",
      queue: "media",
      state: "available",
      attempt: 1
    }
  end

  defp put_avatar_object(key, bytes) do
    S3Config.avatars_bucket_name()
    |> ExAws.S3.put_object(key, bytes)
    |> ExAws.request!()
  end

  # Creates a user + avatar with `original_path` pointing at a real object
  # actually present in local MinIO.
  defp create_avatar_for_user(source \\ :upload) do
    user = user_fixture()
    suffix = Ecto.ULID.generate()
    key = "#{user.id}/#{suffix}/original.png"
    put_avatar_object(key, @tiny_png)

    public_url = S3Config.object_url(key, S3Config.avatars_bucket_name())

    {:ok, avatar} =
      Avatars.create_avatar(user, %{
        source: source,
        original_path: public_url
      })

    {user, avatar}
  end

  # Creates a "completed" avatar for a user and sets it as the user's current avatar.
  defp set_existing_current_avatar(user) do
    {:ok, placeholder} =
      Avatars.create_avatar(user, %{
        source: :upload,
        original_path: "https://example.com/placeholder.webp"
      })

    {:ok, placeholder} =
      Avatars.update_processed_avatar(placeholder, %{
        processing_state: :completed,
        thumb_path: "https://example.com/t.webp",
        profile_path: "https://example.com/p.webp",
        large_path: "https://example.com/l.webp"
      })

    {:ok, _user} = Avatars.set_current_avatar(user, placeholder.id)

    placeholder
  end

  # -------------------------------------------------------------------------
  # perform/1 - avatar not found
  # -------------------------------------------------------------------------

  describe "perform/1 when avatar does not exist" do
    test "discards the job" do
      job = make_oban_job(Ecto.ULID.generate())

      assert {:discard, :avatar_not_found} = AvatarProcessor.perform(job)
    end
  end

  describe "resolve_original_s3_key/1" do
    test "rejects URLs whose object key is not under the avatar owner's user id" do
      user = user_fixture()

      assert {:error, :invalid_avatar_original_path} =
               AvatarProcessor.resolve_original_s3_key(%{
                 user_id: user.id,
                 original_path:
                   "https://cdn.example.org/other-user-id/x/original.webp"
               })
    end
  end

  # -------------------------------------------------------------------------
  # perform/1 - download failures
  # -------------------------------------------------------------------------

  describe "perform/1 when the image download fails" do
    test "returns error and marks the avatar as failed when S3 is unreachable" do
      user = user_fixture()
      suffix = Ecto.ULID.generate()
      key = "#{user.id}/#{suffix}/original.png"

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path: "http://127.0.0.1:99999/avatars/#{key}"
        })

      original = Application.get_env(:ysc, :s3_base_url)
      Application.put_env(:ysc, :s3_base_url, "http://127.0.0.1:1")

      on_exit(fn ->
        if original do
          Application.put_env(:ysc, :s3_base_url, original)
        else
          Application.delete_env(:ysc, :s3_base_url)
        end
      end)

      assert {:error, _} = AvatarProcessor.perform(make_oban_job(avatar.id))

      assert Repo.get!(Avatars.Avatar, avatar.id).processing_state == :failed
    end

    test "returns error and marks the avatar as failed when S3 returns non-200 for the object" do
      user = user_fixture()
      suffix = Ecto.ULID.generate()
      # Never actually uploaded to MinIO, so the public GET 404s.
      key = "#{user.id}/#{suffix}/original.png"

      {:ok, avatar} =
        Avatars.create_avatar(user, %{
          source: :upload,
          original_path:
            S3Config.object_url(key, S3Config.avatars_bucket_name())
        })

      assert {:error, _} = AvatarProcessor.perform(make_oban_job(avatar.id))

      assert Repo.get!(Avatars.Avatar, avatar.id).processing_state == :failed
    end
  end

  # -------------------------------------------------------------------------
  # perform/1 - happy path
  # -------------------------------------------------------------------------

  describe "perform/1 happy path" do
    test "returns :ok and marks the avatar as completed" do
      {_user, avatar} = create_avatar_for_user()

      assert :ok = AvatarProcessor.perform(make_oban_job(avatar.id))

      updated = Repo.get!(Avatars.Avatar, avatar.id)
      assert updated.processing_state == :completed
      assert is_binary(updated.thumb_path) and updated.thumb_path != ""
      assert is_binary(updated.profile_path) and updated.profile_path != ""
      assert is_binary(updated.large_path) and updated.large_path != ""
    end

    test "sets the user's current avatar when the user has none" do
      {user, avatar} = create_avatar_for_user(:upload)

      # Confirm no current avatar before processing
      assert is_nil(Repo.reload!(user).current_avatar_id)

      assert :ok = AvatarProcessor.perform(make_oban_job(avatar.id))

      assert Repo.reload!(user).current_avatar_id == avatar.id
    end

    test "upload source always replaces the current avatar" do
      {user, new_avatar} = create_avatar_for_user(:upload)
      existing = set_existing_current_avatar(user)

      assert Repo.reload!(user).current_avatar_id == existing.id

      assert :ok = AvatarProcessor.perform(make_oban_job(new_avatar.id))

      # Upload source always wins, even when a current avatar exists
      assert Repo.reload!(user).current_avatar_id == new_avatar.id
    end

    test "OAuth source does not replace an existing current avatar" do
      {user, oauth_avatar} = create_avatar_for_user(:google)
      existing = set_existing_current_avatar(user)

      assert Repo.reload!(user).current_avatar_id == existing.id

      assert :ok = AvatarProcessor.perform(make_oban_job(oauth_avatar.id))

      # OAuth source must not override when a current avatar already exists
      assert Repo.reload!(user).current_avatar_id == existing.id
    end

    test "OAuth source sets the current avatar when the user has none" do
      {user, oauth_avatar} = create_avatar_for_user(:google)

      assert is_nil(Repo.reload!(user).current_avatar_id)

      assert :ok = AvatarProcessor.perform(make_oban_job(oauth_avatar.id))

      assert Repo.reload!(user).current_avatar_id == oauth_avatar.id
    end

    test "cleans up all temp files after successful processing" do
      {_user, avatar} = create_avatar_for_user()

      assert :ok = AvatarProcessor.perform(make_oban_job(avatar.id))

      base = Path.join("/tmp/avatar_processor", avatar.id)

      for suffix <- [
            "_raw",
            "_stripped.webp",
            "_thumb.webp",
            "_profile.webp",
            "_large.webp"
          ] do
        refute File.exists?("#{base}#{suffix}"),
               "expected #{suffix} to be deleted after success"
      end
    end

    test "cleans up all temp files after a processing failure" do
      {_user, avatar} = create_avatar_for_user()

      suffix = Ecto.ULID.generate()
      user_id = avatar.user_id
      bad_key = "#{user_id}/#{suffix}/original.png"

      failing_avatar =
        avatar
        |> Ecto.Changeset.change(
          original_path:
            S3Config.object_url(bad_key, S3Config.avatars_bucket_name())
        )
        |> Repo.update!()

      assert {:error, _} =
               AvatarProcessor.perform(make_oban_job(failing_avatar.id))

      base = Path.join("/tmp/avatar_processor", failing_avatar.id)

      for suffix <- [
            "_raw",
            "_stripped.webp",
            "_thumb.webp",
            "_profile.webp",
            "_large.webp"
          ] do
        refute File.exists?("#{base}#{suffix}"),
               "expected #{suffix} to be deleted after failure"
      end
    end
  end
end
