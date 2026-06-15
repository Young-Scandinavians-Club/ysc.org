defmodule YscWeb.AdminPostsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp post_fixture(author, attrs) do
    {:ok, post} =
      %Ysc.Posts.Post{}
      |> Ysc.Posts.Post.new_post_changeset(
        Enum.into(attrs, %{
          user_id: author.id,
          title: "Test Post",
          url_name: "test-post-#{System.unique_integer()}",
          state: :published
        })
      )
      |> Ysc.Repo.insert()

    post
  end

  describe "Admin Posts" do
    setup [:create_admin]

    test "lists posts", %{conn: conn, admin: admin} do
      post_fixture(admin, %{title: "Viking News"})

      {:ok, _view, html} = live(conn, ~p"/admin/posts")
      assert html =~ "Posts"
      assert html =~ "Viking News"
    end

    test "navigates to new post editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts")

      view
      |> element("#admin-posts-new-post")
      |> render_click()

      assert_redirect(view, ~p"/admin/posts/new")
    end

    test "search patches URL with title filter", %{conn: conn, admin: admin} do
      post_fixture(admin, %{title: "Unique Viking Headline XYZ"})

      {:ok, view, _} = live(conn, ~p"/admin/posts")

      _ =
        view
        |> form("#posts-search-form", q: "Unique Viking")
        |> render_change()

      assert_patch(
        view,
        ~p"/admin/posts?#{%{"filters" => %{"0" => %{"field" => "title", "op" => "ilike", "value" => "Unique Viking"}}}}"
      )
    end

    test "does not re-query post authors on each search patch", %{
      conn: conn,
      admin: admin
    } do
      post_fixture(admin, %{title: "Author Cache Headline"})

      {:ok, view, _} = live(conn, ~p"/admin/posts")

      author_filter_pattern = ~r/DISTINCT ON \(.*"user_id"\).*FROM "posts"/is

      {_patch, author_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            view
            |> form("#posts-search-form", q: "Author Cache")
            |> render_change()
          end,
          pattern: author_filter_pattern
        )

      assert author_queries == 0
    end

    test "toggles featured post", %{conn: conn, admin: admin} do
      p1 =
        post_fixture(admin, %{title: "Featured Candidate", featured_post: false})

      _p2 = post_fixture(admin, %{title: "Other Post", featured_post: false})

      {:ok, view, _} = live(conn, ~p"/admin/posts")

      _ =
        view
        |> element(
          "div.hidden.md\\:block button[phx-click='toggle-featured'][phx-value-id='#{p1.id}']"
        )
        |> render_click()

      updated = Ysc.Posts.get_post!(p1.id)
      assert updated.featured_post == true
    end

    test "toggling featured on one post clears featured on another", %{
      conn: conn,
      admin: admin
    } do
      p1 = post_fixture(admin, %{title: "Pin A", featured_post: false})
      p2 = post_fixture(admin, %{title: "Pin B", featured_post: true})

      {:ok, view, _} = live(conn, ~p"/admin/posts")

      view
      |> element(
        "div.hidden.md\\:block button[phx-click='toggle-featured'][phx-value-id='#{p1.id}']"
      )
      |> render_click()

      assert Ysc.Posts.get_post!(p1.id).featured_post == true
      assert Ysc.Posts.get_post!(p2.id).featured_post == false
    end

    test "deletes a draft post from the actions menu", %{
      conn: conn,
      admin: admin
    } do
      draft =
        post_fixture(admin, %{
          title: "Draft To Delete",
          state: :draft,
          url_name: "draft-delete-#{System.unique_integer()}"
        })

      published =
        post_fixture(admin, %{
          title: "Published Stay",
          state: :published,
          url_name: "published-stay-#{System.unique_integer()}"
        })

      {:ok, view, html} = live(conn, ~p"/admin/posts")

      assert html =~ "Draft To Delete"
      refute html =~ ~s/id="post-actions-dt-#{published.id}-delete"/

      view
      |> element("#post-actions-dt-#{draft.id}-delete")
      |> render_click()

      refute render(view) =~ "Draft To Delete"
      assert Ysc.Posts.get_post!(draft.id).state == :deleted
    end

    test "invalid flop params redirect to default posts list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/posts")

      render_patch(view, ~p"/admin/posts?order_by=not_a_real_field")

      assert_patched(view, ~p"/admin/posts")
    end
  end
end
