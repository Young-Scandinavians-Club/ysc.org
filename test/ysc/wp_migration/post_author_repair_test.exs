defmodule Ysc.WpMigration.PostAuthorRepairTest do
  use Ysc.DataCase, async: true

  alias Ysc.AccountsFixtures
  alias Ysc.Posts.Post
  alias Ysc.WpMigration.Load
  alias Ysc.Repo

  setup do
    wrong_author = AccountsFixtures.user_fixture(%{email: "admin@example.com"})
    {:ok, wrong_author: wrong_author}
  end

  test "repair_post_authors updates posts from export author emails", %{
    wrong_author: wrong_author
  } do
    export_dir =
      System.tmp_dir!()
      |> Path.join("wp_post_author_repair_#{System.unique_integer()}")

    File.mkdir_p!(export_dir)

    author =
      AccountsFixtures.user_fixture(%{
        email: "peter@ysc.org",
        first_name: "Peter and Natalia",
        last_name: "Nordström"
      })

    {:ok, post} =
      %Post{user_id: wrong_author.id}
      |> Post.new_post_changeset(%{
        state: "published",
        title: "Club Update",
        url_name: "club-update",
        raw_body: "<p>Hello</p>",
        rendered_body: "<p>Hello</p>",
        published_on: DateTime.utc_now()
      })
      |> Repo.insert()

    posts_json = [
      %{
        "title" => "Club Update",
        "post_name" => "club-update",
        "wp_post_id" => "999",
        "wp_author_id" => "187"
      }
    ]

    users_json = [
      %{
        "wp_user_id" => "187",
        "email" => "peter@ysc.org",
        "first_name" => "Peter and Natalia",
        "last_name" => "Nordström"
      }
    ]

    File.write!(Path.join(export_dir, "posts.json"), Jason.encode!(posts_json))
    File.write!(Path.join(export_dir, "users.json"), Jason.encode!(users_json))

    assert {:ok, %{updated: 1, unchanged: 0, skipped: 0, failed: 0}} =
             Load.repair_post_authors(export_dir)

    updated = Repo.get!(Post, post.id)
    assert updated.user_id == author.id

    on_exit(fn -> File.rm_rf!(export_dir) end)
  end

  test "repair_post_authors supports author_overrides", %{
    wrong_author: wrong_author
  } do
    export_dir =
      System.tmp_dir!()
      |> Path.join("wp_post_author_override_#{System.unique_integer()}")

    File.mkdir_p!(export_dir)

    author =
      AccountsFixtures.user_fixture(%{
        email: "other@example.com",
        first_name: "Peter and Natalia",
        last_name: "Nordström"
      })

    {:ok, post} =
      %Post{user_id: wrong_author.id}
      |> Post.new_post_changeset(%{
        state: "published",
        title: "Override Post",
        url_name: "override-post",
        raw_body: "<p>Hello</p>",
        rendered_body: "<p>Hello</p>",
        published_on: DateTime.utc_now()
      })
      |> Repo.insert()

    posts_json = [
      %{
        "title" => "Override Post",
        "post_name" => "override-post",
        "wp_post_id" => "1000",
        "wp_author_id" => "187"
      }
    ]

    users_json = [
      %{
        "wp_user_id" => "187",
        "email" => "missing@example.com",
        "first_name" => "Peter and Natalia",
        "last_name" => "Nordström"
      }
    ]

    File.write!(Path.join(export_dir, "posts.json"), Jason.encode!(posts_json))
    File.write!(Path.join(export_dir, "users.json"), Jason.encode!(users_json))

    assert {:ok, %{updated: 1}} =
             Load.repair_post_authors(export_dir,
               author_overrides: %{"187" => author.id}
             )

    updated = Repo.get!(Post, post.id)
    assert updated.user_id == author.id

    on_exit(fn -> File.rm_rf!(export_dir) end)
  end

  test "repair_post_authors dry run does not update records", %{
    wrong_author: wrong_author
  } do
    export_dir =
      System.tmp_dir!()
      |> Path.join("wp_post_author_dry_#{System.unique_integer()}")

    File.mkdir_p!(export_dir)

    _author = AccountsFixtures.user_fixture(%{email: "peter@ysc.org"})

    {:ok, post} =
      %Post{user_id: wrong_author.id}
      |> Post.new_post_changeset(%{
        state: "published",
        title: "Dry Run Post",
        url_name: "dry-run-post",
        raw_body: "<p>Hello</p>",
        rendered_body: "<p>Hello</p>",
        published_on: DateTime.utc_now()
      })
      |> Repo.insert()

    posts_json = [
      %{
        "title" => "Dry Run Post",
        "post_name" => "dry-run-post",
        "wp_post_id" => "1001",
        "wp_author_id" => "187"
      }
    ]

    users_json = [%{"wp_user_id" => "187", "email" => "peter@ysc.org"}]

    File.write!(Path.join(export_dir, "posts.json"), Jason.encode!(posts_json))
    File.write!(Path.join(export_dir, "users.json"), Jason.encode!(users_json))

    assert {:ok, %{updated: 1}} =
             Load.repair_post_authors(export_dir, dry_run: true)

    unchanged = Repo.get!(Post, post.id)
    assert unchanged.user_id == wrong_author.id

    on_exit(fn -> File.rm_rf!(export_dir) end)
  end
end
