defmodule Ysc.Posts.GetPublicPostTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Posts
  alias Ysc.Posts.Post
  alias Ysc.Repo

  @raw_body_pattern ~r/raw_body/i
  @secret_pattern ~r/hashed_password|board_bio|upload_data/i
  @unused_column_pattern ~r/deleted_on|featured_post|updated_by_id|"updated_at"/i

  defp insert_post(author, attrs) do
    {rendered_body, attrs} = Map.pop(attrs, :rendered_body)

    defaults = %{
      user_id: author.id,
      title: "Public page body",
      url_name: "public-page-#{System.unique_integer([:positive])}",
      state: :published,
      published_on: DateTime.utc_now() |> DateTime.truncate(:second),
      raw_body: "<p>raw</p>"
    }

    {:ok, post} =
      %Post{}
      |> Post.new_post_changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    if is_binary(rendered_body) do
      post
      |> Ecto.Changeset.change(%{rendered_body: rendered_body})
      |> Repo.update!()
    else
      post
    end
  end

  test "omits raw_body from the SELECT and keeps rendered_body" do
    author = user_fixture()
    marker = "public-page-#{System.unique_integer([:positive])}"

    post =
      insert_post(author, %{
        raw_body: "<p>raw #{marker}</p>",
        rendered_body: "<p>rendered #{marker}</p>"
      })

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
    author = user_fixture()
    marker = "public-url-#{System.unique_integer([:positive])}"
    url_name = "public-url-#{System.unique_integer([:positive])}"

    post =
      insert_post(author, %{
        url_name: url_name,
        raw_body: "<p>raw #{marker}</p>",
        rendered_body: "<p>rendered #{marker}</p>"
      })

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
    author = user_fixture(%{role: :admin})
    marker = "preview-#{System.unique_integer([:positive])}"

    post =
      insert_post(author, %{
        state: :draft,
        published_on: nil,
        raw_body: "<p>raw #{marker}</p>",
        rendered_body: "<p>rendered #{marker}</p>"
      })

    {loaded, raw_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Posts.get_post_for_page(post.id, author) end,
        pattern: @raw_body_pattern,
        caller_pids: [self()]
      )

    assert loaded.id == post.id
    assert loaded.rendered_body == "<p>rendered #{marker}</p>"
    assert is_nil(loaded.raw_body)
    assert raw_cols == 0
  end

  test "omits unused admin columns from the SELECT" do
    author = user_fixture()
    post = insert_post(author, %{title: "Public page slim columns"})

    {sql, _params} =
      Ecto.Adapters.SQL.to_sql(
        :all,
        Repo,
        Posts.ci_query_explain_public_post_query()
      )

    refute sql =~ "deleted_on"
    refute sql =~ "featured_post"
    refute sql =~ "updated_by_id"
    refute sql =~ ~s("updated_at")
    refute sql =~ "raw_body"
    assert sql =~ "rendered_body"
    assert sql =~ "preview_text"
    assert sql =~ "comment_count"
    assert sql =~ "board_position_at_publish"

    {loaded, unused_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Posts.get_public_post(post.id) end,
        pattern: @unused_column_pattern,
        caller_pids: [self()]
      )

    assert loaded.id == post.id
    assert loaded.title == "Public page slim columns"
    assert loaded.url_name == post.url_name
    # Unselected schema defaults (false/nil) still appear on the struct; the
    # SQL above is the load we care about.
    assert unused_cols == 0
  end

  test "page preloads skip author secrets and image upload_data" do
    author = user_fixture()
    post = insert_post(author, %{})

    {loaded, fat_cols} =
      Ysc.QueryCounter.with_query_counter(
        fn -> Posts.get_public_post(post.id) end,
        pattern: @secret_pattern,
        caller_pids: [self()]
      )

    assert loaded.author.id == author.id
    assert loaded.author.first_name
    assert is_nil(loaded.author.hashed_password)
    assert Ecto.assoc_loaded?(loaded.author.current_avatar)
    assert Ecto.assoc_loaded?(loaded.featured_image)
    assert fat_cols == 0
  end
end
