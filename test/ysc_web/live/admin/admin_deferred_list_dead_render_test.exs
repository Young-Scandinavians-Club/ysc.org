defmodule YscWeb.AdminDeferredListDeadRenderTest do
  @moduledoc false

  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

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
end
