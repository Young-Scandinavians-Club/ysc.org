defmodule Ysc.SafeFileTest do
  use ExUnit.Case, async: true

  alias Ysc.SafeFile

  describe "resolve_under_root/2" do
    test "accepts paths under the root" do
      root = SafeFile.event_photo_tmp_root()
      path = Path.join(root, "event-photo-test.jpg")

      assert {:ok, ^path} = SafeFile.resolve_under_root(root, path)
    end

    test "rejects paths outside the root" do
      root = SafeFile.event_photo_tmp_root()

      assert :error = SafeFile.resolve_under_root(root, "/etc/passwd")
    end
  end

  describe "event_photo_tmp_path/3" do
    test "builds a path under the system tmp directory" do
      assert {:ok, path} =
               SafeFile.event_photo_tmp_path("01ABCDEF", "abc123", "photo.jpg")

      assert String.starts_with?(path, SafeFile.event_photo_tmp_root())
      assert String.ends_with?(path, "event-photo-01ABCDEF-abc123.jpg")
    end

    test "rejects traversal in identifiers" do
      assert :error =
               SafeFile.event_photo_tmp_path("../evil", "abc123", "photo.jpg")
    end
  end

  describe "dev_event_photo_path/2" do
    test "builds a path under the dev stub directory" do
      assert {:ok, path} = SafeFile.dev_event_photo_path("event-1", "photo.jpg")

      assert String.starts_with?(path, SafeFile.dev_event_photos_root())
      assert String.ends_with?(path, "event-1/photo.jpg")
    end

    test "rejects path segments in the filename" do
      assert :error = SafeFile.dev_event_photo_path("event-1", "../secret.jpg")
    end
  end
end
