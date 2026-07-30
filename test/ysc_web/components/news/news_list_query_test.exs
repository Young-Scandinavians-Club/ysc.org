defmodule YscWeb.NewsListQueryTest do
  @moduledoc false

  # Query-counter assertions must run with async: false — parallel tests can add
  # unrelated image queries and make counts flaky in CI.
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Posts.Post
  alias Ysc.Repo

  test "uses preloaded featured images without extra image queries" do
    author = user_fixture()

    {:ok, image} =
      %Ysc.Media.Image{
        user_id: author.id,
        raw_image_path: "https://example.com/news-cover.jpg",
        processing_state: :completed,
        title: "Cover"
      }
      |> Repo.insert()

    %Post{}
    |> Post.new_post_changeset(%{
      user_id: author.id,
      title: "Post With Cover",
      url_name: "post-with-cover-#{System.unique_integer()}",
      state: :published,
      raw_body: "Test body",
      rendered_body: "Test body",
      published_on: DateTime.utc_now() |> DateTime.truncate(:second),
      featured_post: false,
      featured_image_id: image.id
    })
    |> Repo.insert!()

    images_pattern = ~r/FROM "images"/i

    {_html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn -> render_component(YscWeb.NewsListLive, %{id: "news-list"}) end,
        pattern: images_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
  end
end
