defmodule YscWeb.FeedController do
  use YscWeb, :controller

  alias Ysc.Events
  alias Ysc.Posts
  alias YscWeb.Feeds.AtomFeed

  def events(conn, _params) do
    xml = Events.list_upcoming_events(50) |> AtomFeed.events_feed()

    conn
    |> put_resp_content_type("application/atom+xml")
    |> text(xml)
  end

  def posts(conn, _params) do
    xml =
      Posts.list_recent_published_posts_for_feed(50) |> AtomFeed.posts_feed()

    conn
    |> put_resp_content_type("application/atom+xml")
    |> text(xml)
  end
end
