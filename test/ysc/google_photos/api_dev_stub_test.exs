defmodule Ysc.GooglePhotos.Api.DevStubTest do
  use ExUnit.Case, async: true

  alias Ysc.GooglePhotos.Api.DevStub
  alias Ysc.GooglePhotos.Limits

  @dev_event_dir Path.join(["tmp/dev_event_photos", "event-1"])

  setup do
    on_exit(fn -> File.rm_rf(@dev_event_dir) end)
    :ok
  end

  test "create_album returns dev album id" do
    assert {:ok, "dev-album-event-1"} =
             DevStub.create_album(
               "token",
               "Summer Party — Jun 1, 2026",
               "event-1"
             )
  end

  test "upload_bytes writes to tmp and returns token" do
    bytes = "fake jpeg"

    assert {:ok, token} =
             DevStub.upload_bytes("token", bytes, "photo.jpg", "event-1")

    assert is_binary(token)
    assert String.starts_with?(token, "dev-upload-")

    assert [stored | _] = File.ls!(@dev_event_dir)
    assert String.starts_with?(stored, "photo-")
    assert String.ends_with?(stored, ".jpg")
    assert File.regular?(Path.join(@dev_event_dir, stored))
  end

  test "upload_bytes rejects oversize photos" do
    huge = :binary.copy(<<0>>, Limits.max_photo_bytes() + 1)

    assert {:error, :photo_too_large} =
             DevStub.upload_bytes("token", huge, "big.jpg", "event-1")
  end

  test "upload_bytes accepts large videos under 20 GB cap" do
    bytes = :binary.copy(<<0>>, 1024)

    assert {:ok, _token} =
             DevStub.upload_bytes("token", bytes, "clip.mp4", "event-1")
  end

  test "upload_bytes rejects nil event_id" do
    assert {:error, :invalid_event_id} =
             DevStub.upload_bytes("token", "bytes", "photo.jpg", nil)
  end
end
