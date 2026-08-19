defmodule YscWeb.MediaLibraryUploadTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.UploadEntry
  alias YscWeb.MediaLibraryUpload

  defp fake_socket(max_file_size) do
    %Socket{
      assigns: %{uploads: %{media_uploads: %{max_file_size: max_file_size}}}
    }
  end

  defp entry(attrs) do
    struct(
      %UploadEntry{upload_config: :media_uploads, client_name: "photo.png"},
      attrs
    )
  end

  test "presigns a unique public key instead of public/<client filename>" do
    entry = entry(client_name: "club-logo.png", client_type: "image/png")

    assert {:ok, meta, _socket} =
             MediaLibraryUpload.presign(entry, fake_socket(1_000_000))

    assert meta.uploader == "S3"
    refute meta.key == "public/club-logo.png"
    assert meta.key =~ ~r{^public/[^/]+/club-logo\.png$}
    assert meta.fields["key"] == meta.key
    assert meta.fields["content-type"] == "image/png"
  end

  test "two uploads of the same filename get different object keys" do
    entry = entry(client_name: "club-logo.png")

    assert {:ok, first, _} =
             MediaLibraryUpload.presign(entry, fake_socket(1_000_000))

    assert {:ok, second, _} =
             MediaLibraryUpload.presign(entry, fake_socket(1_000_000))

    assert first.key != second.key
  end

  test "derives Content-Type from the extension, not the browser MIME type" do
    entry =
      entry(client_name: "club-logo.jpg", client_type: "text/html")

    assert {:ok, meta, _socket} =
             MediaLibraryUpload.presign(entry, fake_socket(1_000_000))

    assert meta.fields["content-type"] == "image/jpeg"
    refute meta.fields["content-type"] == "text/html"
  end

  test "strips client-supplied directories from the object key" do
    entry = entry(client_name: "nested/path/club-logo.webp")

    assert {:ok, meta, _socket} =
             MediaLibraryUpload.presign(entry, fake_socket(1_000_000))

    assert meta.key =~ ~r{^public/[^/]+/club-logo\.webp$}
    refute meta.key =~ "nested"
  end
end
