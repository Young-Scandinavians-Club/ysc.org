defmodule YscWeb.EventPhotoUploadTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.UploadEntry
  alias Ysc.GooglePhotos.Limits
  alias YscWeb.EventPhotoUpload

  defp fake_socket(max_file_size) do
    %Socket{
      assigns: %{uploads: %{photos: %{max_file_size: max_file_size}}}
    }
  end

  defp policy_max_bytes(meta) do
    meta.fields["policy"]
    |> Base.decode64!()
    |> Jason.decode!()
    |> Map.fetch!("conditions")
    |> Enum.find_value(fn
      ["content-length-range", 0, max] -> max
      _ -> nil
    end)
  end

  test "presigns a key scoped under the collection with the original extension" do
    entry = %UploadEntry{client_name: "party.mp4"}
    collection_id = "01J000000000000000000000"

    assert {:ok, meta, _socket} =
             EventPhotoUpload.presign(entry, fake_socket(1_000), collection_id)

    assert meta.uploader == "S3"

    assert String.starts_with?(
             meta.key,
             "event_photo_uploads/#{collection_id}/"
           )

    assert String.ends_with?(meta.key, ".mp4")
    assert meta.fields["content-type"] == "video/mp4"
  end

  test "normalizes the extension case" do
    entry = %UploadEntry{client_name: "IMG_0001.HEIC"}

    assert {:ok, meta, _socket} =
             EventPhotoUpload.presign(
               entry,
               fake_socket(1_000),
               "collection-id"
             )

    assert String.ends_with?(meta.key, ".heic")
    assert meta.fields["content-type"] == "image/heic"
  end

  test "Finding 100: S3 POST policy uses the photo cap, not the 20 GB video cap" do
    entry = %UploadEntry{client_name: "party.jpg"}

    assert {:ok, meta, _socket} =
             EventPhotoUpload.presign(
               entry,
               fake_socket(20 * 1024 * 1024 * 1024),
               "cid"
             )

    assert policy_max_bytes(meta) == Limits.max_photo_bytes()
    assert policy_max_bytes(meta) < Limits.max_video_bytes()
  end

  test "Finding 100: S3 POST policy keeps the video cap for videos" do
    entry = %UploadEntry{client_name: "clip.mp4"}

    assert {:ok, meta, _socket} =
             EventPhotoUpload.presign(entry, fake_socket(1_000), "cid")

    assert policy_max_bytes(meta) == Limits.max_video_bytes()
  end

  test "Finding 100: refuses to presign unsupported names onto the public bucket" do
    entry = %UploadEntry{client_name: "notes.html"}

    assert {:error, %{reason: reason}, _socket} =
             EventPhotoUpload.presign(entry, fake_socket(1_000), "cid")

    assert reason == Limits.error_message(:unsupported_type)
  end
end
