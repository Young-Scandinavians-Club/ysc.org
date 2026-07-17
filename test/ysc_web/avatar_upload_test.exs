defmodule YscWeb.AvatarUploadTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.S3Config
  alias Ysc.Accounts.User
  alias Ysc.Repo
  alias YscWeb.AvatarUpload

  defp upload_socket!(max_file_size \\ 10_000_000) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        uploads: %{
          avatar: %{max_file_size: max_file_size}
        }
      }
    }
  end

  defp entry!(name, type \\ "image/jpeg") do
    %{client_name: name, client_type: type}
  end

  describe "presign/4" do
    test "uses server-controlled content type from extension" do
      user = user_fixture()
      socket = upload_socket!()

      assert {:ok, meta, ^socket} =
               AvatarUpload.presign(
                 entry!("avatar.png", "text/html"),
                 socket,
                 user
               )

      assert meta.uploader == "S3"
      assert meta.key =~ "#{user.id}/"
      assert meta.key =~ "/original.png"
      assert meta.fields["content-type"] == "image/png"
      assert is_binary(meta.url)
      assert is_map(meta.fields)
    end

    test "defaults unknown extensions to webp" do
      user = user_fixture()
      socket = upload_socket!()

      assert {:ok, meta, _} =
               AvatarUpload.presign(entry!("avatar.bin"), socket, user)

      assert meta.key =~ "/original.webp"
      assert meta.fields["content-type"] == "image/webp"
    end

    test "respects configured max file size" do
      user = user_fixture()
      socket = upload_socket!(5_000_000)

      assert {:ok, meta, _} =
               AvatarUpload.presign(entry!("avatar.jpg"), socket, user)

      policy = meta.fields["policy"] |> Base.decode64!() |> Jason.decode!()

      assert Enum.any?(policy["conditions"], fn
               ["content-length-range", 0, 5_000_000] -> true
               _ -> false
             end)
    end
  end

  describe "consume_upload_meta/2" do
    test "creates avatar and enqueues processing job" do
      user = user_fixture()
      key = "#{user.id}/#{Ecto.ULID.generate()}/original.webp"

      assert {:ok, avatar} = AvatarUpload.consume_upload_meta(user, %{key: key})
      assert avatar.user_id == user.id

      assert avatar.original_path ==
               S3Config.object_url(key, S3Config.avatars_bucket_name())
    end

    test "returns error when avatar creation fails" do
      user = user_fixture()
      user_id = user.id
      Repo.delete!(user)

      assert {:error, %Ecto.Changeset{}} =
               AvatarUpload.consume_upload_meta(%User{id: user_id}, %{
                 key: "#{user_id}/#{Ecto.ULID.generate()}/original.webp"
               })
    end
  end

  describe "upload outcome helpers" do
    test "upload_succeeded?/1" do
      assert AvatarUpload.upload_succeeded?([{:ok, %{id: "1"}}])
      refute AvatarUpload.upload_succeeded?([{:error, :boom}])
      refute AvatarUpload.upload_succeeded?([])

      assert AvatarUpload.upload_succeeded?([
               {:error, :first},
               {:ok, %{id: "2"}}
             ])
    end

    test "upload_failed?/1" do
      assert AvatarUpload.upload_failed?([{:error, :boom}])
      refute AvatarUpload.upload_failed?([{:ok, %{id: "1"}}])
      refute AvatarUpload.upload_failed?([])

      assert AvatarUpload.upload_failed?([
               {:ok, %{id: "1"}},
               {:error, :second}
             ])
    end
  end
end
