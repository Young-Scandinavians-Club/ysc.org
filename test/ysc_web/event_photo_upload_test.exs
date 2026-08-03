defmodule YscWeb.EventPhotoUploadTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.UploadEntry
  alias YscWeb.EventPhotoUpload

  defp fake_socket(max_file_size) do
    %Socket{
      assigns: %{uploads: %{photos: %{max_file_size: max_file_size}}}
    }
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
end
