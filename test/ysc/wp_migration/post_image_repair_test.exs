defmodule Ysc.WpMigration.PostImageRepairTest do
  use Ysc.DataCase, async: true

  alias Ysc.AccountsFixtures
  alias Ysc.Media.Image
  alias Ysc.Posts.Post
  alias Ysc.WpMigration.Load
  alias Ysc.Repo

  test "repair_post_images rewrites WordPress image URLs to migration media URLs" do
    export_dir =
      System.tmp_dir!()
      |> Path.join("wp_post_image_repair_#{System.unique_integer()}")

    File.mkdir_p!(export_dir)

    uploader = AccountsFixtures.user_fixture()

    {:ok, image} =
      %Image{user_id: uploader.id}
      |> Image.add_image_changeset(%{
        title: "Club Photo",
        alt_text: "Club Photo",
        raw_image_path: "https://assets.ysc.org/migration/123/photo.jpg",
        optimized_image_path: "https://assets.ysc.org/123_optimized.webp",
        upload_data: %{
          "wp_attachment_id" => "123",
          "key" => "migration/123/photo.jpg"
        },
        processing_state: "completed"
      })
      |> Repo.insert()

    {:ok, post} =
      %Post{user_id: uploader.id}
      |> Post.new_post_changeset(%{
        state: "published",
        title: "Club Update",
        url_name: "club-update",
        raw_body:
          ~s(<img src="https://old.example.com/wp-content/uploads/photo.jpg" class="wp-image-123" />),
        rendered_body:
          ~s(<img src="https://old.example.com/wp-content/uploads/photo.jpg" class="wp-image-123" />),
        published_on: DateTime.utc_now()
      })
      |> Repo.insert()

    posts_json = [
      %{
        "title" => "Club Update",
        "post_name" => "club-update",
        "wp_post_id" => "999",
        "post_content" =>
          ~s(<img src="https://old.example.com/wp-content/uploads/photo.jpg" class="wp-image-123" alt="Club Photo" />),
        "wp_attachment_ids_in_content" => ["123"]
      }
    ]

    File.write!(Path.join(export_dir, "posts.json"), Jason.encode!(posts_json))

    assert {:ok, %{updated: 1, unchanged: 0, skipped: 0, failed: 0}} =
             Load.repair_post_images(export_dir)

    updated = Repo.get!(Post, post.id)
    assert updated.image_id == image.id
    assert updated.raw_body =~ "https://assets.ysc.org/123_optimized.webp"
    assert updated.rendered_body =~ "https://assets.ysc.org/123_optimized.webp"
    refute updated.rendered_body =~ "migration/123/photo.jpg"
    refute updated.rendered_body =~ "old.example.com"

    on_exit(fn -> File.rm_rf!(export_dir) end)
  end

  test "repair_post_images dry run does not update records" do
    export_dir =
      System.tmp_dir!()
      |> Path.join("wp_post_image_dry_#{System.unique_integer()}")

    File.mkdir_p!(export_dir)

    uploader = AccountsFixtures.user_fixture()

    {:ok, _image} =
      %Image{user_id: uploader.id}
      |> Image.add_image_changeset(%{
        title: "Club Photo",
        alt_text: "Club Photo",
        raw_image_path: "https://assets.ysc.org/migration/456/photo.jpg",
        upload_data: %{
          "wp_attachment_id" => "456",
          "key" => "migration/456/photo.jpg"
        },
        processing_state: "completed"
      })
      |> Repo.insert()

    old_body =
      ~s(<img src="https://old.example.com/wp-content/uploads/photo.jpg" class="wp-image-456" />)

    {:ok, post} =
      %Post{user_id: uploader.id}
      |> Post.new_post_changeset(%{
        state: "published",
        title: "Dry Run Post",
        url_name: "dry-run-post",
        raw_body: old_body,
        rendered_body: old_body,
        published_on: DateTime.utc_now()
      })
      |> Repo.insert()

    posts_json = [
      %{
        "title" => "Dry Run Post",
        "post_name" => "dry-run-post",
        "wp_post_id" => "1000",
        "post_content" =>
          ~s(<img src="https://old.example.com/wp-content/uploads/photo.jpg" class="wp-image-456" />),
        "wp_attachment_ids_in_content" => ["456"]
      }
    ]

    File.write!(Path.join(export_dir, "posts.json"), Jason.encode!(posts_json))

    assert {:ok, %{updated: 1}} =
             Load.repair_post_images(export_dir, dry_run: true)

    unchanged = Repo.get!(Post, post.id)
    assert unchanged.raw_body == old_body

    on_exit(fn -> File.rm_rf!(export_dir) end)
  end
end
