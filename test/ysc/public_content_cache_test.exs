defmodule Ysc.PublicContentCacheTest do
  use Ysc.DataCase, async: false

  alias Ysc.{Posts, PublicContentCache}
  alias Ysc.Posts.Post
  alias Ysc.Repo

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures, only: [event_fixture: 1]

  setup do
    PublicContentCache.invalidate()
    Cachex.clear(:ysc_cache)
    :ok
  end

  describe "subscribe/0" do
    test "receives invalidation broadcast" do
      PublicContentCache.subscribe()

      PublicContentCache.invalidate_posts()

      assert_receive {:public_content_cache_invalidated, version}
      assert is_integer(version)
    end
  end

  describe "list_recent_posts/1" do
    test "cache miss then hit" do
      user = user_fixture()

      %Post{}
      |> Post.new_post_changeset(%{
        "title" => "Cached Post",
        "state" => "published",
        "featured_post" => false,
        "user_id" => user.id,
        "published_on" => DateTime.utc_now()
      })
      |> Repo.insert!()

      posts1 = PublicContentCache.list_recent_posts(5)
      posts2 = PublicContentCache.list_recent_posts(5)

      assert posts1 != []
      assert Enum.map(posts1, & &1.id) == Enum.map(posts2, & &1.id)
    end

    test "unpublishing via Posts.update_post removes post from cached list" do
      author = user_fixture(%{role: "admin"})

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "To Unpublish",
            "body" => "Body",
            "url_name" => "to-unpublish-#{System.unique_integer()}",
            "state" => "published",
            "featured_post" => false,
            "published_on" => DateTime.utc_now()
          },
          author
        )

      assert Enum.any?(
               PublicContentCache.list_recent_posts(10),
               &(&1.id == post.id)
             )

      assert {:ok, _} =
               Posts.update_post(
                 post,
                 %{"state" => "draft", "published_on" => nil},
                 author
               )

      posts = PublicContentCache.list_recent_posts(10)
      refute Enum.any?(posts, &(&1.id == post.id))
    end

    test "deleting via Posts.update_post removes post from cached list" do
      author = user_fixture(%{role: "admin"})

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "To Delete",
            "body" => "Body",
            "url_name" => "to-delete-#{System.unique_integer()}",
            "state" => "published",
            "featured_post" => false,
            "published_on" => DateTime.utc_now()
          },
          author
        )

      PublicContentCache.list_recent_posts(10)

      assert {:ok, _} =
               Posts.update_post(
                 post,
                 %{
                   "state" => "deleted",
                   "deleted_on" => DateTime.utc_now(),
                   "published_on" => nil,
                   "featured_post" => false
                 },
                 author
               )

      posts = PublicContentCache.list_recent_posts(10)
      refute Enum.any?(posts, &(&1.id == post.id))
    end

    test "invalidation refetches after post update" do
      user = user_fixture()

      {:ok, post} =
        %Post{}
        |> Post.new_post_changeset(%{
          "title" => "Original",
          "state" => "published",
          "featured_post" => false,
          "user_id" => user.id,
          "published_on" => DateTime.utc_now()
        })
        |> Repo.insert()

      PublicContentCache.list_recent_posts(10)

      post
      |> Post.update_post_changeset(%{"title" => "Updated Title"})
      |> Repo.update!()

      PublicContentCache.invalidate_posts()

      posts = PublicContentCache.list_recent_posts(10)

      assert Enum.any?(
               posts,
               &(&1.id == post.id and &1.title == "Updated Title")
             )
    end
  end

  describe "list_upcoming_events/1" do
    test "returns upcoming events from cache" do
      event = event_fixture(%{title: "Cache Event #{System.unique_integer()}"})

      events1 = PublicContentCache.list_upcoming_events(10)
      events2 = PublicContentCache.list_upcoming_events(10)

      assert Enum.any?(events1, &(&1.id == event.id))
      assert Enum.map(events1, & &1.id) == Enum.map(events2, & &1.id)
    end
  end
end
