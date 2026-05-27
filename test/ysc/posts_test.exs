defmodule Ysc.PostsTest do
  @moduledoc """
  Tests for the Ysc.Posts context module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Posts
  alias Ysc.Posts.{Post, Comment}
  alias Ysc.Repo

  setup do
    author = user_fixture(%{role: "admin"})
    regular_user = user_fixture()

    %{author: author, regular_user: regular_user}
  end

  describe "create_post/2" do
    test "creates a post when authorized", %{author: author} do
      attrs = %{
        "title" => "Test Post",
        "preview_text" => "A preview",
        "body" => "Post body content",
        "url_name" => "test-post",
        "state" => "draft"
      }

      assert {:ok, %Post{} = post} = Posts.create_post(attrs, author)
      assert post.title == "Test Post"
      assert post.user_id == author.id
    end

    test "returns error when user is not authorized", %{regular_user: user} do
      attrs = %{"title" => "Test Post", "body" => "Content"}

      assert {:error, :unauthorized} = Posts.create_post(attrs, user)
    end
  end

  describe "list_posts_by_ids/2" do
    test "returns posts in the same order as ids", %{author: author} do
      {:ok, post_a} =
        Posts.create_post(
          %{"title" => "A", "body" => "Body", "url_name" => "post-a"},
          author
        )

      {:ok, post_b} =
        Posts.create_post(
          %{"title" => "B", "body" => "Body", "url_name" => "post-b"},
          author
        )

      posts = Posts.list_posts_by_ids([post_b.id, post_a.id])
      assert Enum.map(posts, & &1.id) == [post_b.id, post_a.id]
    end
  end

  describe "get_post/2" do
    test "returns post by id", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "test"},
          author
        )

      result = Posts.get_post(post.id)
      assert result.id == post.id
    end

    test "preloads associations when requested", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "body" => "Body",
            "url_name" => "preload-get-post"
          },
          author
        )

      result = Posts.get_post(post.id, [:author, :featured_image])
      assert result.id == post.id
      assert Ecto.assoc_loaded?(result.author)
      assert Ecto.assoc_loaded?(result.featured_image)
    end

    test "returns nil for non-existent post" do
      assert Posts.get_post(Ecto.ULID.generate()) == nil
    end
  end

  describe "get_post!/1" do
    test "returns post by id", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "test-get"},
          author
        )

      result = Posts.get_post!(post.id)
      assert result.id == post.id
    end

    test "raises for non-existent post" do
      assert_raise Ecto.NoResultsError, fn ->
        Posts.get_post!(Ecto.ULID.generate())
      end
    end
  end

  describe "get_post_by_url_name/2" do
    test "returns post by url_name", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "body" => "Body",
            "url_name" => "my-unique-slug"
          },
          author
        )

      result = Posts.get_post_by_url_name("my-unique-slug")
      assert result.id == post.id
    end

    test "returns nil for non-existent url_name" do
      assert Posts.get_post_by_url_name("nonexistent-slug") == nil
    end

    test "preloads associations when requested", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "body" => "Body",
            "url_name" => "preload-url-name"
          },
          author
        )

      result =
        Posts.get_post_by_url_name("preload-url-name", [
          :author,
          :featured_image
        ])

      assert result.id == post.id
      assert Ecto.assoc_loaded?(result.author)
      assert Ecto.assoc_loaded?(result.featured_image)
    end
  end

  describe "get_post_by_id_or_url_name/1" do
    test "returns post by id", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "id-or-url"},
          author
        )

      result = Posts.get_post_by_id_or_url_name(post.id)
      assert result.id == post.id
    end

    test "returns post by ULID-shaped url_name when id differs", %{
      author: author
    } do
      ulid_slug = Ecto.ULID.generate()

      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => ulid_slug},
          author
        )

      refute to_string(post.id) == ulid_slug
      assert Posts.get_post_by_id_or_url_name(ulid_slug).id == post.id
    end
  end

  describe "update_post/4" do
    test "updates post when authorized", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Original",
            "body" => "Body",
            "url_name" => "update-test"
          },
          author
        )

      assert {:ok, updated} =
               Posts.update_post(post, %{"title" => "Updated"}, author)

      assert updated.title == "Updated"
    end

    test "returns error when not authorized", %{
      author: author,
      regular_user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Original", "body" => "Body", "url_name" => "auth-test"},
          author
        )

      assert {:error, :unauthorized} =
               Posts.update_post(post, %{"title" => "Updated"}, user)
    end

    test "publishing post when author has no board position sets board_position_at_publish to nil",
         %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Member post",
            "body" => "Body",
            "url_name" => "member-post-nil-board",
            "state" => "draft"
          },
          author
        )

      assert post.board_position_at_publish == nil

      assert {:ok, published} =
               Posts.update_post(
                 post,
                 %{
                   "state" => "published",
                   "published_on" => DateTime.utc_now()
                 },
                 author
               )

      assert published.state == :published
      assert published.board_position_at_publish == nil
    end

    test "sets board_position_at_publish from author when publishing", %{
      author: author
    } do
      {:ok, author} =
        author
        |> Ecto.Changeset.change(%{board_position: :president})
        |> Repo.update()

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Board snapshot",
            "body" => "Body",
            "url_name" => "board-snapshot",
            "state" => "draft"
          },
          author
        )

      published_on = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, published} =
               Posts.update_post(
                 post,
                 %{
                   "state" => "published",
                   "published_on" => published_on
                 },
                 author
               )

      assert published.state == :published
      assert published.board_position_at_publish == "president"
    end

    test "does not override board_position_at_publish when already provided", %{
      author: author
    } do
      {:ok, author} =
        author
        |> Ecto.Changeset.change(%{board_position: :president})
        |> Repo.update()

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Manual board field",
            "body" => "Body",
            "url_name" => "board-manual",
            "state" => "draft"
          },
          author
        )

      published_on = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, published} =
               Posts.update_post(
                 post,
                 %{
                   "state" => "published",
                   "published_on" => published_on,
                   "board_position_at_publish" => "treasurer"
                 },
                 author
               )

      assert published.board_position_at_publish == "treasurer"
    end

    test "uses atom keys for board snapshot when params use atom state", %{
      author: author
    } do
      {:ok, author} =
        author
        |> Ecto.Changeset.change(%{board_position: :secretary})
        |> Repo.update()

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Atom keys",
            "body" => "Body",
            "url_name" => "board-atoms",
            "state" => "draft"
          },
          author
        )

      published_on = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, published} =
               Posts.update_post(
                 post,
                 %{state: :published, published_on: published_on},
                 author
               )

      assert published.board_position_at_publish == "secretary"
    end
  end

  describe "list_posts/1 and list_posts/2" do
    test "returns published posts", %{author: author} do
      {:ok, post1} =
        Posts.create_post(
          %{
            "title" => "Published 1",
            "body" => "Body",
            "url_name" => "pub-1",
            "state" => "published",
            "published_on" => DateTime.truncate(DateTime.utc_now(), :second)
          },
          author
        )

      # Make it not featured
      post1
      |> Ecto.Changeset.change(featured_post: false)
      |> Repo.update!()

      result = Posts.list_posts(10)
      assert result != []
    end
  end

  describe "count_published_posts/0" do
    test "counts only published posts", %{author: author} do
      {:ok, _} =
        Posts.create_post(
          %{
            "title" => "Published",
            "body" => "Body",
            "url_name" => "count-pub",
            "state" => "published"
          },
          author
        )

      {:ok, _} =
        Posts.create_post(
          %{
            "title" => "Draft",
            "body" => "Body",
            "url_name" => "count-draft",
            "state" => "draft"
          },
          author
        )

      assert Posts.count_published_posts() >= 1
    end
  end

  describe "add_comment_to_post/2" do
    test "adds a comment to a post", %{author: author, regular_user: user} do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "comment-test"},
          author
        )

      params = %{"post_id" => post.id, "text" => "Great post!"}

      assert {:ok, %Comment{} = comment} =
               Posts.add_comment_to_post(params, user)

      assert comment.text == "Great post!"
      assert comment.user_id == user.id
      assert comment.post_id == post.id
    end

    test "increments comment count on post", %{
      author: author,
      regular_user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "body" => "Body",
            "url_name" => "comment-count-test"
          },
          author
        )

      # comment_count starts as nil or 0
      assert post.comment_count in [nil, 0]

      Posts.add_comment_to_post(
        %{"post_id" => post.id, "text" => "Comment 1"},
        user
      )

      Posts.add_comment_to_post(
        %{"post_id" => post.id, "text" => "Comment 2"},
        user
      )

      updated = Posts.get_post!(post.id)
      assert updated.comment_count == 2
    end

    test "returns error changeset when comment is invalid", %{
      author: author,
      regular_user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "body" => "Body",
            "url_name" => "comment-invalid"
          },
          author
        )

      assert {:error, %Ecto.Changeset{}} =
               Posts.add_comment_to_post(
                 %{"post_id" => post.id, "text" => ""},
                 user
               )
    end
  end

  describe "get_comments_for_post/2" do
    test "returns comments for a post", %{author: author, regular_user: user} do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "list-comments"},
          author
        )

      Posts.add_comment_to_post(
        %{"post_id" => post.id, "text" => "Comment 1"},
        user
      )

      Posts.add_comment_to_post(
        %{"post_id" => post.id, "text" => "Comment 2"},
        user
      )

      comments = Posts.get_comments_for_post(post.id)
      assert length(comments) == 2
    end

    test "preloads associations when requested", %{
      author: author,
      regular_user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "body" => "Body",
            "url_name" => "list-comments-pre"
          },
          author
        )

      Posts.add_comment_to_post(
        %{"post_id" => post.id, "text" => "Comment 1"},
        user
      )

      [c] = Posts.get_comments_for_post(post.id, [:author])
      assert c.text == "Comment 1"
      assert Ecto.assoc_loaded?(c.author)
    end
  end

  describe "sort_comments_for_render/1" do
    test "sorts top-level comments with replies" do
      # Create mock comments
      parent = %Comment{id: "1", comment_id: nil, text: "Parent"}
      reply = %Comment{id: "2", comment_id: "1", text: "Reply"}

      sorted = Posts.sort_comments_for_render([parent, reply])

      # Parent should come first, followed by reply
      assert length(sorted) == 2
    end

    test "orders reply before parent when reply appears first in input" do
      parent = %Comment{id: "p1", comment_id: nil, text: "Parent"}
      reply = %Comment{id: "r1", comment_id: "p1", text: "Reply"}

      sorted = Posts.sort_comments_for_render([reply, parent])
      assert Enum.map(sorted, & &1.id) == ["p1", "r1"]
    end
  end

  describe "count_posts_with_url_name/1" do
    test "counts posts with matching url_name", %{author: author} do
      {:ok, _} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "slug-count"},
          author
        )

      {:ok, _} =
        Posts.create_post(
          %{
            "title" => "Test 2",
            "body" => "Body",
            "url_name" => "slug-count-2"
          },
          author
        )

      count = Posts.count_posts_with_url_name("slug-count")
      assert count >= 2
    end
  end

  describe "get_featured_post/0" do
    test "returns featured published post", %{author: author} do
      {:ok, featured} =
        Posts.create_post(
          %{
            "title" => "Featured",
            "body" => "Body",
            "url_name" => "featured-post",
            "state" => "published",
            "featured_post" => true,
            "published_on" => DateTime.truncate(DateTime.utc_now(), :second)
          },
          author
        )

      result = Posts.get_featured_post()
      assert result.id == featured.id
      assert result.featured_post == true
    end

    test "returns nil when no featured post exists" do
      assert Posts.get_featured_post() == nil
    end
  end

  describe "list_posts/2" do
    test "returns paginated published posts using keyset cursor", %{
      author: author
    } do
      now = DateTime.utc_now()

      for i <- 1..5 do
        {:ok, _} =
          Posts.create_post(
            %{
              "title" => "Post #{i}",
              "body" => "Body",
              "url_name" => "post-#{i}",
              "state" => "published",
              "featured_post" => false,
              "published_on" =>
                DateTime.truncate(DateTime.add(now, -i, :second), :second)
            },
            author
          )
      end

      # First page: cursor is nil
      page1 = Posts.list_posts(nil, 2)
      assert length(page1) == 2

      # Second page: cursor is the published_on of the last item on page 1
      cursor = List.last(page1).published_on
      page2 = Posts.list_posts(cursor, 2)
      assert length(page2) >= 2

      # Pages must not overlap
      page1_ids = Enum.map(page1, & &1.id)
      page2_ids = Enum.map(page2, & &1.id)
      assert Enum.empty?(page1_ids -- (page1_ids -- page2_ids))
    end
  end

  describe "list_posts_paginated/1" do
    test "returns paginated posts with filters", %{author: author} do
      {:ok, _} =
        Posts.create_post(
          %{
            "title" => "Published",
            "body" => "Body",
            "url_name" => "paginated-1",
            "state" => "published"
          },
          author
        )

      {:ok, _} =
        Posts.create_post(
          %{
            "title" => "Draft",
            "body" => "Body",
            "url_name" => "paginated-2",
            "state" => "draft"
          },
          author
        )

      params = %{limit: 10, offset: 0}
      {:ok, {entries, meta}} = Posts.list_posts_paginated(params)
      # Should return at least the published and draft posts (not deleted)
      assert meta.total_count >= 1
      assert entries != []
    end

    test "filters by search_term using fuzzy search", %{author: author} do
      {:ok, _} =
        Posts.create_post(
          %{
            "title" => "UniqueSearchableTitleXYZ",
            "body" => "Body",
            "url_name" => "search-fuzzy-1",
            "state" => "published"
          },
          author
        )

      params = %{limit: 20, offset: 0}

      {:ok, {entries, _meta}} =
        Posts.list_posts_paginated(params,
          search_term: "UniqueSearchableTitleXYZ"
        )

      assert Enum.any?(entries, &(&1.title == "UniqueSearchableTitleXYZ"))
    end

    test "normalizes a bare search string as opts", %{author: author} do
      {:ok, _} =
        Posts.create_post(
          %{
            "title" => "BareStringSearchToken",
            "body" => "Body",
            "url_name" => "search-bare-1",
            "state" => "published"
          },
          author
        )

      params = %{limit: 20, offset: 0}

      {:ok, {entries, _meta}} =
        Posts.list_posts_paginated(params, "BareStringSearchToken")

      assert Enum.any?(entries, &(&1.title == "BareStringSearchToken"))
    end

    test "applies date_from and date_to when valid ISO dates", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "DateFiltered",
            "body" => "Body",
            "url_name" => "date-filter-1",
            "state" => "published"
          },
          author
        )

      day = DateTime.to_date(post.inserted_at)
      date_from = Date.to_iso8601(Date.add(day, -1))
      date_to = Date.to_iso8601(Date.add(day, 1))

      params = %{limit: 50, offset: 0}

      {:ok, {entries, _meta}} =
        Posts.list_posts_paginated(params,
          date_from: date_from,
          date_to: date_to
        )

      ids = Enum.map(entries, & &1.id)
      assert post.id in ids
    end

    test "ignores invalid date strings for date filters", %{author: author} do
      {:ok, _} =
        Posts.create_post(
          %{
            "title" => "InvalidDateFilter",
            "body" => "Body",
            "url_name" => "date-bad-1",
            "state" => "published"
          },
          author
        )

      params = %{limit: 50, offset: 0}

      assert {:ok, {_entries, _meta}} =
               Posts.list_posts_paginated(params,
                 date_from: "not-a-date",
                 date_to: "also-bad"
               )
    end

    test "returns error when Flop params exceed configured limits" do
      assert {:error, _} = Posts.list_posts_paginated(%{limit: 9999, offset: 0})
    end
  end

  describe "get_latest_comments/1" do
    test "returns latest comments from published posts", %{
      author: author,
      regular_user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Published Post",
            "body" => "Body",
            "url_name" => "latest-comments",
            "state" => "published",
            "published_on" => DateTime.truncate(DateTime.utc_now(), :second)
          },
          author
        )

      Posts.add_comment_to_post(
        %{"post_id" => post.id, "text" => "Comment 1"},
        user
      )

      Posts.add_comment_to_post(
        %{"post_id" => post.id, "text" => "Comment 2"},
        user
      )

      comments = Posts.get_latest_comments(5)
      assert length(comments) >= 2
      assert Enum.any?(comments, &(&1.text == "Comment 1"))
    end
  end

  describe "reply comments" do
    test "adds reply to existing comment", %{author: author, regular_user: user} do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "reply-test"},
          author
        )

      {:ok, parent_comment} =
        Posts.add_comment_to_post(
          %{"post_id" => post.id, "text" => "Parent comment"},
          user
        )

      {:ok, reply} =
        Posts.add_comment_to_post(
          %{
            "post_id" => post.id,
            "text" => "Reply",
            "comment_id" => parent_comment.id
          },
          user
        )

      assert reply.comment_id == parent_comment.id
      assert reply.text == "Reply"
    end

    test "sort_comments_for_render/1 organizes replies under parents", %{
      author: author,
      regular_user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "sort-test"},
          author
        )

      {:ok, parent} =
        Posts.add_comment_to_post(
          %{"post_id" => post.id, "text" => "Parent"},
          user
        )

      {:ok, _reply1} =
        Posts.add_comment_to_post(
          %{
            "post_id" => post.id,
            "text" => "Reply 1",
            "comment_id" => parent.id
          },
          user
        )

      {:ok, _reply2} =
        Posts.add_comment_to_post(
          %{
            "post_id" => post.id,
            "text" => "Reply 2",
            "comment_id" => parent.id
          },
          user
        )

      comments = Posts.get_comments_for_post(post.id)
      sorted = Posts.sort_comments_for_render(comments)

      # Parent should be first, followed by its replies
      assert length(sorted) >= 3
      assert Enum.at(sorted, 0).id == parent.id
    end
  end

  describe "get_all_authors/0" do
    test "returns all unique post authors", %{author: author} do
      {:ok, _} =
        Posts.create_post(
          %{"title" => "Post 1", "body" => "Body", "url_name" => "author-1"},
          author
        )

      authors = Posts.get_all_authors()
      assert authors != []
      assert Enum.any?(authors, fn {_name, user_id} -> user_id == author.id end)
    end
  end

  describe "get_post_by_url_name!/1" do
    test "returns post by url_name", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "url-name-bang"},
          author
        )

      found = Posts.get_post_by_url_name!("url-name-bang")
      assert found.id == post.id
    end

    test "raises for non-existent url_name" do
      assert_raise Ecto.NoResultsError, fn ->
        Posts.get_post_by_url_name!("nonexistent-slug")
      end
    end
  end

  describe "get_comment!/2" do
    test "returns comment by id", %{author: author, regular_user: user} do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "get-comment"},
          author
        )

      {:ok, comment} =
        Posts.add_comment_to_post(
          %{"post_id" => post.id, "text" => "Test comment"},
          user
        )

      found = Posts.get_comment!(comment.id)
      assert found.id == comment.id
    end

    test "preloads associations when requested", %{
      author: author,
      regular_user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test",
            "body" => "Body",
            "url_name" => "get-comment-pre"
          },
          author
        )

      {:ok, comment} =
        Posts.add_comment_to_post(
          %{"post_id" => post.id, "text" => "Test comment"},
          user
        )

      found = Posts.get_comment!(comment.id, [:author, :post])
      assert Ecto.assoc_loaded?(found.author)
      assert Ecto.assoc_loaded?(found.post)
    end

    test "returns nil for missing comment id" do
      assert Posts.get_comment!(Ecto.ULID.generate()) == nil
    end
  end

  describe "get_insert_index_for_comment/1" do
    test "returns 0 for top-level comment" do
      comment = %Comment{comment_id: nil}
      assert Posts.get_insert_index_for_comment(comment) == 0
    end

    test "returns index for reply comment", %{
      author: author,
      regular_user: user
    } do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "index-test"},
          author
        )

      {:ok, parent} =
        Posts.add_comment_to_post(
          %{"post_id" => post.id, "text" => "Parent"},
          user
        )

      {:ok, reply} =
        Posts.add_comment_to_post(
          %{"post_id" => post.id, "text" => "Reply", "comment_id" => parent.id},
          user
        )

      index = Posts.get_insert_index_for_comment(reply)
      assert is_integer(index)
      assert index >= 0
    end
  end

  describe "post_topic/1" do
    test "returns topic for post", %{author: author} do
      {:ok, post} =
        Posts.create_post(
          %{"title" => "Test", "body" => "Body", "url_name" => "topic-test"},
          author
        )

      topic = Posts.post_topic(post.id)
      assert is_binary(topic)
    end
  end

  describe "public post page access (#353)" do
    test "get_public_post/2 returns only published posts", %{author: author} do
      {:ok, draft} =
        Posts.create_post(
          %{
            "title" => "Draft",
            "body" => "Body",
            "url_name" => "public-access-draft-#{System.unique_integer()}"
          },
          author
        )

      {:ok, published} =
        Posts.create_post(
          %{
            "title" => "Published",
            "body" => "Body",
            "url_name" => "public-access-published-#{System.unique_integer()}",
            "state" => "published",
            "published_on" => DateTime.utc_now() |> DateTime.truncate(:second)
          },
          author
        )

      assert Posts.get_public_post(draft.id) == nil
      assert %Post{id: id} = Posts.get_public_post(published.id)
      assert id == published.id
    end

    test "get_post_for_page/3 hides drafts from members but allows staff preview",
         %{
           author: author,
           regular_user: member
         } do
      {:ok, draft} =
        Posts.create_post(
          %{
            "title" => "Staff preview draft",
            "body" => "Body",
            "url_name" => "staff-preview-draft-#{System.unique_integer()}"
          },
          author
        )

      admin = user_fixture(%{role: :admin})
      volunteer = user_fixture(%{role: :volunteer})

      assert Posts.get_post_for_page(draft.id, member) == nil
      assert %Post{id: id} = Posts.get_post_for_page(draft.id, admin)
      assert id == draft.id
      assert %Post{id: id} = Posts.get_post_for_page(draft.id, volunteer)
      assert id == draft.id
    end

    test "get_post_for_page_by_url_name/3 mirrors id-based access rules", %{
      author: author,
      regular_user: member
    } do
      url_name = "url-name-access-#{System.unique_integer()}"

      {:ok, draft} =
        Posts.create_post(
          %{"title" => "Draft", "body" => "Body", "url_name" => url_name},
          author
        )

      admin = user_fixture(%{role: :admin})

      assert Posts.get_post_for_page_by_url_name(url_name, member) == nil

      assert %Post{id: id} =
               Posts.get_post_for_page_by_url_name(url_name, admin)

      assert id == draft.id
    end
  end
end
