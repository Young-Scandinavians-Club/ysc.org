defmodule YscWeb.S3.DirectUploadTest do
  use ExUnit.Case, async: true

  alias Ysc.S3Config
  alias YscWeb.S3.DirectUpload

  defp fake_socket do
    %Phoenix.LiveView.Socket{assigns: %{uploads: %{}}}
  end

  defp decode_policy(meta) do
    meta.fields["policy"] |> Base.decode64!() |> Jason.decode!()
  end

  describe "presign/2" do
    test "returns LiveView S3 uploader meta for media uploads" do
      socket = fake_socket()
      key = "event_photo_uploads/collection-id/unique.jpg"

      assert {:ok, meta, ^socket} =
               DirectUpload.presign(socket,
                 kind: :media,
                 key: key,
                 content_type: "image/jpeg",
                 max_file_size: 1_000_000
               )

      assert meta.uploader == "S3"
      assert meta.key == key
      assert meta.url == S3Config.upload_url()
      assert meta.fields["key"] == key
      assert meta.fields["content-type"] == "image/jpeg"
      assert meta.fields["acl"] == "public-read"
      assert is_binary(meta.fields["policy"])
      assert is_binary(meta.fields["x-amz-signature"])
    end

    test "uses the avatars bucket and upload URL for :avatars" do
      key = "user-id/avatar-id/original.webp"

      assert {:ok, meta, _socket} =
               DirectUpload.presign(fake_socket(),
                 kind: :avatars,
                 key: key,
                 content_type: "image/webp",
                 max_file_size: 5_000_000
               )

      assert meta.url == S3Config.avatars_upload_url()
      assert meta.fields["key"] == key

      policy = decode_policy(meta)

      assert Enum.any?(policy["conditions"], fn
               %{"bucket" => bucket} -> bucket == S3Config.avatars_bucket_name()
               _ -> false
             end)
    end

    test "uses the media bucket for :media" do
      assert {:ok, meta, _socket} =
               DirectUpload.presign(fake_socket(),
                 kind: :media,
                 key: "public/unique/club-logo.png",
                 content_type: "image/png",
                 max_file_size: 2_000_000
               )

      policy = decode_policy(meta)

      assert Enum.any?(policy["conditions"], fn
               %{"bucket" => bucket} -> bucket == S3Config.bucket_name()
               _ -> false
             end)
    end

    test "signs the configured max file size into the policy" do
      assert {:ok, meta, _socket} =
               DirectUpload.presign(fake_socket(),
                 kind: :media,
                 key: "public/unique/photo.jpg",
                 content_type: "image/jpeg",
                 max_file_size: 4_000_000
               )

      policy = decode_policy(meta)

      assert Enum.any?(policy["conditions"], fn
               ["content-length-range", 0, 4_000_000] -> true
               _ -> false
             end)
    end

    test "honors a custom expires_in" do
      assert {:ok, meta, _socket} =
               DirectUpload.presign(fake_socket(),
                 kind: :media,
                 key: "event_photo_uploads/id/clip.mp4",
                 content_type: "video/mp4",
                 max_file_size: 10_000,
                 expires_in: :timer.hours(2)
               )

      policy = decode_policy(meta)
      {:ok, expiration, 0} = DateTime.from_iso8601(policy["expiration"])
      diff_ms = DateTime.diff(expiration, DateTime.utc_now(), :millisecond)

      assert_in_delta diff_ms, :timer.hours(2), 5_000
    end

    test "raises when a required option is missing" do
      assert_raise KeyError, fn ->
        DirectUpload.presign(fake_socket(),
          kind: :media,
          content_type: "image/jpeg",
          max_file_size: 1_000
        )
      end
    end

    test "raises for an unsupported kind" do
      assert_raise ArgumentError, ~r/unsupported DirectUpload kind/, fn ->
        DirectUpload.presign(fake_socket(),
          kind: :expense_reports,
          key: "private/file.pdf",
          content_type: "application/pdf",
          max_file_size: 1_000
        )
      end
    end
  end

  describe "credentials/0" do
    test "returns the SigV4 map from S3Config" do
      creds = DirectUpload.credentials()

      assert creds.region == S3Config.region()
      assert creds.access_key_id == S3Config.aws_access_key_id()
      assert creds.secret_access_key == S3Config.aws_secret_access_key()
    end
  end
end
