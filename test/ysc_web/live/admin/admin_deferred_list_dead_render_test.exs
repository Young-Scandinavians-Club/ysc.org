defmodule YscWeb.AdminDeferredListDeadRenderTest do
  @moduledoc false

  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.ScanningFixtures

  setup %{conn: conn} do
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

  test "dead render skips posts list query and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    post_fixture(admin, %{title: "Static Render Post"})

    posts_pattern = ~r/FROM "posts"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/posts")
          |> html_response(200)
        end,
        pattern: posts_pattern
      )

    assert query_count == 0
    assert html =~ "Loading posts"
    refute html =~ "Static Render Post"
  end

  test "dead render skips events list query and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    event_fixture(%{title: "Static Render Event", organizer_id: admin.id})

    events_pattern = ~r/FROM "events"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/events")
          |> html_response(200)
        end,
        pattern: events_pattern
      )

    assert query_count == 0
    assert html =~ "Loading events"
    refute html =~ "Static Render Event"
  end

  test "dead render skips users list query and shows loading state", %{
    conn: conn
  } do
    user_fixture(%{first_name: "Static", last_name: "User"})

    users_pattern = ~r/FROM "users"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/users")
          |> html_response(200)
        end,
        pattern: users_pattern
      )

    assert query_count == 0
    assert html =~ "Loading users"
    refute html =~ "Static User"
  end

  test "dead render loads review route without list meta", %{conn: conn} do
    pending_user =
      user_fixture(%{
        state: "pending_approval",
        first_name: "Review",
        last_name: "Render"
      })

    signup_application_fixture(pending_user)

    html =
      conn
      |> get("/admin/users/#{pending_user.id}/review")
      |> html_response(200)

    assert html =~ "Review Application"
    assert html =~ "Review Render"
    assert html =~ "Loading users"
  end

  test "dead render skips scanner sessions query and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    scan_session_fixture(%{
      created_by_id: admin.id,
      name: "Static Render Session"
    })

    sessions_pattern = ~r/FROM "scan_sessions"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/scanner/sessions")
          |> html_response(200)
        end,
        pattern: sessions_pattern
      )

    assert query_count == 0
    assert html =~ "Loading sessions"
    refute html =~ "Static Render Session"
  end

  describe "connected list loading" do
    test "events list replaces loading placeholder after connect", %{
      conn: conn,
      admin: admin
    } do
      event_fixture(%{title: "Deferred Load Event", organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events")
      html = render(view)

      refute html =~ "Loading events…"
      assert html =~ "Deferred Load Event"
      assert has_element?(view, "#admin_events_list")
    end

    test "posts list replaces loading placeholder after connect", %{
      conn: conn,
      admin: admin
    } do
      post_fixture(admin, %{title: "Deferred Load Post"})

      {:ok, view, _html} = live(conn, ~p"/admin/posts")
      html = render(view)

      refute html =~ "Loading posts…"
      assert html =~ "Deferred Load Post"
      assert has_element?(view, "#admin_posts_list")
    end

    test "users list replaces loading placeholder after connect", %{conn: conn} do
      user_fixture(%{first_name: "Deferred", last_name: "Loaduser"})

      {:ok, view, _html} = live(conn, ~p"/admin/users")
      html = render(view)

      refute html =~ "Loading users…"
      assert html =~ "Deferred Loaduser"
      assert has_element?(view, "#admin_users_list")
    end
  end
end
