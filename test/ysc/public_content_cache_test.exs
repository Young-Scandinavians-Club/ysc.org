defmodule Ysc.PublicContentCacheTest do
  use Ysc.DataCase, async: false

  @moduletag process_caches: true

  alias Ysc.{Posts, PublicContentCache}
  alias Ysc.Posts.Post
  alias Ysc.Repo

  import Ecto.Query
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

      assert_receive {:public_content_cache_invalidated, :posts, version}
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

  describe "editor autosave (stub %Post{})" do
    setup do
      author = user_fixture(%{role: "admin"})

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Live Article",
            "body" => "Body",
            "url_name" => "live-article-#{System.unique_integer([:positive])}",
            "state" => "published",
            "featured_post" => false,
            "published_on" => DateTime.utc_now()
          },
          author
        )

      %{author: author, post: post}
    end

    test "content edits to a published post refresh the cached list", %{
      author: author,
      post: post
    } do
      assert Enum.any?(
               PublicContentCache.list_recent_posts(10),
               &(&1.id == post.id)
             )

      assert {:ok, _} =
               Posts.update_post_editor(
                 %Post{id: post.id},
                 %{"title" => "Edited Title"},
                 author
               )

      assert Enum.any?(
               PublicContentCache.list_recent_posts(10),
               &(&1.id == post.id and &1.title == "Edited Title")
             )
    end

    test "cached post page is dropped when the post is edited", %{
      author: author,
      post: post
    } do
      load = fn -> Posts.get_post!(post.id) end

      assert PublicContentCache.fetch_post_page("page", load).title ==
               "Live Article"

      assert {:ok, _} =
               Posts.update_post_editor(
                 %Post{id: post.id},
                 %{"title" => "Edited Title"},
                 author
               )

      assert PublicContentCache.fetch_post_page("page", load).title ==
               "Edited Title"
    end

    test "draft edits refresh cached post pages", %{author: author} do
      {:ok, draft} =
        Posts.create_post(
          %{
            "title" => "Draft",
            "body" => "Body",
            "url_name" => "draft-#{System.unique_integer([:positive])}",
            "state" => "draft",
            "featured_post" => false
          },
          author
        )

      load = fn -> Posts.get_post!(draft.id) end
      assert PublicContentCache.fetch_post_page("draft", load).title == "Draft"

      assert {:ok, _} =
               Posts.update_post_editor(
                 %Post{id: draft.id},
                 %{"title" => "Draft v2"},
                 author
               )

      assert PublicContentCache.fetch_post_page("draft", load).title ==
               "Draft v2"
    end

    test "reprocessing the cover image refreshes list and page caches", %{
      post: post
    } do
      image = Ysc.MerchFixtures.image_fixture()

      Repo.update_all(from(p in Post, where: p.id == ^post.id),
        set: [image_id: image.id]
      )

      load = fn -> Posts.get_post!(post.id) |> Repo.preload(:featured_image) end

      assert PublicContentCache.fetch_post_page("cover", load).featured_image.optimized_image_path ==
               nil

      assert [%{featured_image: %{optimized_image_path: nil}}] =
               Enum.filter(
                 PublicContentCache.list_recent_posts(10),
                 &(&1.id == post.id)
               )

      Ysc.Media.update_processed_image(image, %{
        optimized_image_path: "optimized.webp"
      })

      assert PublicContentCache.fetch_post_page("cover", load).featured_image.optimized_image_path ==
               "optimized.webp"

      assert [%{featured_image: %{optimized_image_path: "optimized.webp"}}] =
               Enum.filter(
                 PublicContentCache.list_recent_posts(10),
                 &(&1.id == post.id)
               )
    end
  end

  describe "invalidate_caches_for_image/1" do
    test "ignores images no post uses and non-ids" do
      image = Ysc.MerchFixtures.image_fixture()

      {:ok, before_version} =
        Cachex.get(:ysc_cache, "public_content:version:posts")

      assert :ok = Posts.invalidate_caches_for_image(image.id)
      assert :ok = Posts.invalidate_caches_for_image(nil)

      assert {:ok, ^before_version} =
               Cachex.get(:ysc_cache, "public_content:version:posts")
    end
  end

  describe "ci_query_explain targets" do
    test "build queries" do
      assert %Ecto.Query{} = Posts.ci_query_explain_post_using_image_query()
      assert %Ecto.Query{} = Posts.ci_query_explain_published_post_by_id_query()
    end
  end

  describe "cross-node invalidation" do
    test "a version replicated from another node drops cached post pages" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      load = fn -> Agent.get_and_update(counter, &{&1 + 1, &1 + 1}) end

      assert PublicContentCache.fetch_post_page("remote", load) == 1
      assert PublicContentCache.fetch_post_page("remote", load) == 1

      version_key = "public_content:version:post_pages"
      {:ok, stale_version} = Cachex.get(:ysc_cache, version_key)

      # Bump through the real publisher and capture what it broadcasts.
      Phoenix.PubSub.subscribe(Ysc.PubSub, Ysc.DistributedCache.topic())
      PublicContentCache.invalidate_post_pages()
      this_node = node()

      assert_receive {:distributed_cache_put, ^this_node, :ysc_cache,
                      ^version_key, version, opts}

      # Rewind to what a node that hasn't received the broadcast yet sees.
      Cachex.put(:ysc_cache, version_key, stale_version)
      assert PublicContentCache.fetch_post_page("remote", load) == 1

      # Replay the broadcast as another node's write (Sync skips its own node).
      send(
        Process.whereis(Ysc.DistributedCache.Sync),
        {:distributed_cache_put, :other@node, :ysc_cache, version_key, version,
         opts}
      )

      :sys.get_state(Ysc.DistributedCache.Sync)

      assert PublicContentCache.fetch_post_page("remote", load) == 2
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
