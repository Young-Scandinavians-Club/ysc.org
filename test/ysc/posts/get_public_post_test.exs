defmodule Ysc.Posts.GetPublicPostTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Posts
  alias Ysc.Posts.Post
  alias Ysc.Repo

  @raw_body_pattern ~r/raw_body/i
  @secret_pattern ~r/hashed_password|board_bio/i

  defp insert_post(author, attrs) do
    defaults = %{
      user_id: author.id,
      title: "Public page body",
      url_name: "public-page-#{System.unique_integer([:positive])}",
      raw_body: "<p>raw</p>",
      state: :published,
      published_on: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    {:ok, post} =
      %Post{}
      |> Post.new_post_changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    post
  end

  test "omits raw_body from the SELECT and keeps rendered_body" do
    marker = "public-page-#{System.unique_integer([:positive])}"
    author = user_fixture()

    post =
      insert_post(author, %{
        title: "Public page body",
        raw_body: "<p>raw #{marker}</p>"
      })

    post
    |> Ecto.Changeset.change(%{rendered_body: "<p>rendered #{marker}</p>"})
    |> Repo.update!()

    {loaded, raw_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Posts.get_public_post(post.id) end,
        pattern: @raw_body_pattern,
        caller_pids: [self()]
      )

    assert %Post{id: id} = loaded
    assert id == post.id
    assert loaded.rendered_body == "<p>rendered #{marker}</p>"
    assert is_nil(loaded.raw_body)
    assert raw_cols == 0
  end

  test "get_public_post_by_url_name/1 also omits raw_body" do
    marker = "public-url-#{System.unique_integer([:positive])}"
    author = user_fixture()
    url_name = "public-url-#{System.unique_integer([:positive])}"

    post =
      insert_post(author, %{
        title: "Public page by url name",
        url_name: url_name,
        raw_body: "<p>raw #{marker}</p>"
      })

    post
    |> Ecto.Changeset.change(%{rendered_body: "<p>rendered #{marker}</p>"})
    |> Repo.update!()

    {loaded, raw_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Posts.get_public_post_by_url_name(url_name) end,
        pattern: @raw_body_pattern,
        caller_pids: [self()]
      )

    assert loaded.id == post.id
    assert loaded.rendered_body == "<p>rendered #{marker}</p>"
    assert is_nil(loaded.raw_body)
    assert raw_cols == 0
  end

  test "staff preview on the public page omits raw_body" do
    marker = "preview-#{System.unique_integer([:positive])}"
    admin = user_fixture(%{role: :admin})

    post =
      insert_post(admin, %{
        title: "Draft preview body",
        state: :draft,
        published_on: nil,
        raw_body: "<p>raw #{marker}</p>"
      })

    post
    |> Ecto.Changeset.change(%{rendered_body: "<p>rendered #{marker}</p>"})
    |> Repo.update!()

    {loaded, raw_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Posts.get_post_for_page(post.id, admin) end,
        pattern: @raw_body_pattern,
        caller_pids: [self()]
      )

    assert loaded.id == post.id
    assert loaded.rendered_body == "<p>rendered #{marker}</p>"
    assert is_nil(loaded.raw_body)
    assert raw_cols == 0
  end

  test "page preloads skip author secrets" do
    author = user_fixture()
    post = insert_post(author, %{title: "Slim author"})

    {loaded, secret_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          Posts.get_post_for_page(
            post.id,
            nil,
            Posts.public_page_preloads()
          )
        end,
        pattern: @secret_pattern,
        caller_pids: [self()]
      )

    assert loaded.author.id == author.id
    assert is_nil(loaded.author.hashed_password)
    assert Ecto.assoc_loaded?(loaded.author.current_avatar)
    assert Ecto.assoc_loaded?(loaded.featured_image)
    assert secret_cols == 0
  end
end
