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
      post = post_fixture(admin, %{title: "Viking News"})

      {:ok, view, html} = live(conn, ~p"/admin/posts")
      assert html =~ "Posts"
      assert html =~ "Viking News"
      assert has_element?(view, "#admin-posts-mobile")
      assert has_element?(view, "#admin-post-card-#{post.id}")
      assert has_element?(view, "#admin-help-link-posts-publish")
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

    test "renders date range filter inputs", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/posts")
      render_async(view, 5000)

      assert has_element?(view, "#filter-posts-date-from")
      assert has_element?(view, "#filter-posts-date-to")
    end

    test "date range filter patches URL with date_from and date_to", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/admin/posts")
      render_async(view, 5000)

      view
      |> form("#posts-filter-form", %{
        date_from: "2026-01-01",
        date_to: "2026-03-31"
      })
      |> render_change()

      path = assert_patch(view)
      assert path =~ "date_from=2026-01-01"
      assert path =~ "date_to=2026-03-31"
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

    test "renders pagination on the desktop table when results span pages", %{
      conn: conn,
      admin: admin
    } do
      # default_limit is 50, so 51 posts forces a second page.
      for i <- 1..51 do
        post_fixture(admin, %{
          title: "Paged Post #{i}",
          url_name: "paged-post-#{System.unique_integer()}"
        })
      end

      {:ok, view, _html} = live(conn, ~p"/admin/posts")
      render_async(view, 5000)

      # The pagination nav must render inside the desktop-only table
      # container. The mobile list is `md:hidden`, so a nav that only lives
      # there is invisible on desktop.
      assert has_element?(
               view,
               "div.hidden.md\\:block nav[aria-label='Pagination'] a[aria-label='Go to page 2']"
             )
    end
  end

  describe "editing presence" do
    setup [:create_admin]

    test "shows an avatar on the row of a post currently being edited", %{
      conn: conn,
      admin: admin
    } do
      post = post_fixture(admin, %{title: "Being edited"})
      other_admin = user_fixture(%{role: "admin", first_name: "Jamie"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "row-tab-#{System.unique_integer([:positive])}"},
          :post,
          post.id,
          other_admin
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts")

      assert html =~ "Jamie"
      assert html =~ "is editing"
    end

    test "does not show the current admin's own presence", %{
      conn: conn,
      admin: admin
    } do
      post = post_fixture(admin, %{title: "Own tab open"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "self-row-tab-#{System.unique_integer([:positive])}"},
          :post,
          post.id,
          admin
        )

      {:ok, _view, html} = live(conn, ~p"/admin/posts")

      refute html =~ "is editing"
    end

    test "updates row avatars live when another admin starts editing", %{
      conn: conn,
      admin: admin
    } do
      post = post_fixture(admin, %{title: "Live update row"})

      {:ok, view, html} = live(conn, ~p"/admin/posts")
      refute html =~ "is editing"

      other_admin = user_fixture(%{role: "admin", first_name: "Taylor"})

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: "live-row-tab-#{System.unique_integer([:positive])}"},
          :post,
          post.id,
          other_admin
        )

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: YscWeb.Admin.EditingPresence.topic(:post),
        event: "presence_diff",
        payload: %{
          joins: %{"k" => %{metas: [%{resource_id: post.id}]}},
          leaves: %{}
        }
      })

      html = render(view)
      assert html =~ "Taylor"
      assert html =~ "is editing"
    end

    test "clears row avatars when the other admin leaves", %{
      conn: conn,
      admin: admin
    } do
      post = post_fixture(admin, %{title: "Leave update row"})
      other_admin = user_fixture(%{role: "admin", first_name: "Taylor"})
      socket_id = "leave-row-tab-#{System.unique_integer([:positive])}"

      {:ok, _ref} =
        YscWeb.Admin.EditingPresence.track(
          %{id: socket_id},
          :post,
          post.id,
          other_admin
        )

      {:ok, view, html} = live(conn, ~p"/admin/posts")
      assert html =~ "Taylor"
      assert html =~ "is editing"

      :ok = YscWeb.Admin.EditingPresence.untrack(%{id: socket_id}, :post)

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: YscWeb.Admin.EditingPresence.topic(:post),
        event: "presence_diff",
        payload: %{
          joins: %{},
          leaves: %{"k" => %{metas: [%{resource_id: post.id}]}}
        }
      })

      html = render(view)
      refute html =~ "is editing"
    end

    test "ignores presence_diff for a post that is not on this page", %{
      conn: conn,
      admin: admin
    } do
      post_fixture(admin, %{title: "Visible post"})

      {:ok, view, _html} = live(conn, ~p"/admin/posts")

      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: YscWeb.Admin.EditingPresence.topic(:post),
        event: "presence_diff",
        payload: %{
          joins: %{
            "k" => %{metas: [%{resource_id: Ecto.ULID.generate()}]}
          },
          leaves: %{
            "k2" => %{metas: [%{resource_id: Ecto.ULID.generate()}]}
          }
        }
      })

      html = render(view)
      assert html =~ "Visible post"
      refute html =~ "is editing"
    end
  end

  describe "last edited by" do
    setup [:create_admin]

    test "is not shown on the listing page", %{conn: conn, admin: admin} do
      post_fixture(admin, %{title: "Not on listing"})

      {:ok, _view, html} = live(conn, ~p"/admin/posts")

      refute html =~ "Last edited by"
    end
  end
end
