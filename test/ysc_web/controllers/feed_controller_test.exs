defmodule YscWeb.FeedControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Posts

  describe "GET /feeds/posts.atom" do
    test "returns atom+xml with published post entries", %{conn: conn} do
      admin = user_fixture(%{role: :admin})
      url_name = "feed-post-#{System.unique_integer([:positive])}"

      {:ok, _post} =
        Posts.create_post(
          %{
            "title" => "Feed Post Title",
            "preview_text" => "Preview line",
            "raw_body" => "<p>Hello</p>",
            "rendered_body" => "<p>Hello</p>",
            "url_name" => url_name,
            "state" => "published",
            "published_on" => DateTime.utc_now() |> DateTime.truncate(:second)
          },
          admin
        )

      conn = get(conn, ~p"/feeds/posts.atom")

      assert response(conn, 200) =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert hd(get_resp_header(conn, "content-type")) =~ "application/atom+xml"
      body = response(conn, 200)
      assert body =~ "Feed Post Title"
      assert body =~ "/posts/#{url_name}"
    end

    test "entry summary is plain text without raw HTML from preview_text", %{
      conn: conn
    } do
      admin = user_fixture(%{role: :admin})
      url_name = "feed-plain-#{System.unique_integer([:positive])}"
      marker = "Atom summary#{System.unique_integer([:positive])}"

      {:ok, _post} =
        Posts.create_post(
          %{
            "title" => "Plain Text Feed Post",
            "preview_text" => "Line one<br>Line two<strong>#{marker}</strong>",
            "raw_body" => "<p>Body</p>",
            "rendered_body" => "<p>Body</p>",
            "url_name" => url_name,
            "state" => "published",
            "published_on" => DateTime.utc_now() |> DateTime.truncate(:second)
          },
          admin
        )

      body = get(conn, ~p"/feeds/posts.atom") |> response(200)

      assert body =~ marker
      assert body =~ "Line one"
      assert body =~ "Line two"
      refute body =~ "<strong>"
      refute body =~ "<br>"
    end
  end

  describe "GET /feeds/events.atom" do
    test "returns atom+xml with upcoming event entries", %{conn: conn} do
      admin = user_fixture(%{role: :admin})
      title = "Feed Event #{System.unique_integer([:positive])}"
      event = event_fixture(%{organizer_id: admin.id, title: title})

      conn = get(conn, ~p"/feeds/events.atom")

      assert response(conn, 200) =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert hd(get_resp_header(conn, "content-type")) =~ "application/atom+xml"
      body = response(conn, 200)
      assert body =~ title
      assert body =~ "/events/#{event.id}"
    end

    test "includes rendered event body HTML in the entry content", %{conn: conn} do
      admin = user_fixture(%{role: :admin})
      marker = "atom-body-#{System.unique_integer([:positive])}"
      title = "Feed Body Event #{System.unique_integer([:positive])}"
      event = event_fixture(%{organizer_id: admin.id, title: title})

      event
      |> Ecto.Changeset.change(%{rendered_details: "<p>#{marker}</p>"})
      |> Ysc.Repo.update!()

      body = get(conn, ~p"/feeds/events.atom") |> response(200)

      assert body =~ title
      assert body =~ marker
    end
  end

  describe "HTML feed discovery" do
    test "home page includes alternate links to atom feeds", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ ~s(rel="alternate")
      assert html =~ ~s(type="application/atom+xml")
      assert html =~ "/feeds/events.atom"
      assert html =~ "/feeds/posts.atom"
      assert html =~ ~s(title="YSC Events")
      assert html =~ ~s(title="YSC Club News")
    end
  end
end
