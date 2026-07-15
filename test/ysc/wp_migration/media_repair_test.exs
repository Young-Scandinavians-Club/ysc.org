defmodule Ysc.WpMigration.MediaRepairTest do
  use Ysc.DataCase, async: true

  alias Ysc.Media.Image
  alias Ysc.WpMigration.Load
  alias Ysc.Repo

  import Ecto.Query

  setup do
    user = Ysc.AccountsFixtures.user_fixture()
    {:ok, user: user}
  end

  test "repair_migration_media fixes AppleDouble raw paths", %{user: user} do
    export_dir =
      System.tmp_dir!()
      |> Path.join("wp_media_repair_#{System.unique_integer()}")

    media_dir = Path.join(export_dir, "media/123")
    File.mkdir_p!(media_dir)
    File.write!(Path.join(media_dir, "._file.jpg"), "appledouble")
    File.write!(Path.join(media_dir, "file.jpg"), "real-image-bytes")

    %Image{}
    |> Image.add_image_changeset(%{
      raw_image_path: "https://assets.ysc.org/migration/123/._file.jpg",
      user_id: user.id,
      upload_data: %{"wp_attachment_id" => "123"}
    })
    |> Repo.insert!()

    assert {:ok, %{repaired: 1, skipped: 0, failed: 0}} =
             Load.repair_migration_media(export_dir)

    image = Repo.get_by!(Image, user_id: user.id)

    assert image.raw_image_path ==
             URI.encode(Ysc.S3Config.object_url("migration/123/file.jpg"))

    on_exit(fn -> File.rm_rf!(export_dir) end)
  end

  test "repair_migration_media dry run does not update records", %{user: user} do
    export_dir =
      System.tmp_dir!()
      |> Path.join("wp_media_repair_dry_#{System.unique_integer()}")

    media_dir = Path.join(export_dir, "media/456")
    File.mkdir_p!(media_dir)
    File.write!(Path.join(media_dir, "file.png"), "real-image-bytes")

    broken_path = "https://assets.ysc.org/migration/456/._file.png"

    %Image{}
    |> Image.add_image_changeset(%{
      raw_image_path: broken_path,
      user_id: user.id,
      upload_data: %{"wp_attachment_id" => "456"}
    })
    |> Repo.insert!()

    assert {:ok, %{repaired: 1, skipped: 0, failed: 0}} =
             Load.repair_migration_media(export_dir, dry_run: true)

    image = Repo.one!(from i in Image, where: i.user_id == ^user.id)
    assert image.raw_image_path == broken_path

    on_exit(fn -> File.rm_rf!(export_dir) end)
  end
end
