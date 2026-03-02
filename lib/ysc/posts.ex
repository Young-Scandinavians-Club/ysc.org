defmodule Ysc.Posts do
  @moduledoc """
  The Posts context.
  """

  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Posts.Post
  alias Ysc.Posts.Comment
  alias YscWeb.Authorization.Policy
  alias Ysc.Accounts.User

  def get_post(id, preloads \\ []) do
    Repo.get(Post, id) |> Repo.preload(preloads)
  end

  def get_post!(id) do
    Repo.get!(Post, id)
  end

  def get_post_by_url_name(url_name, preloads \\ []) do
    Repo.get_by(Post, url_name: url_name) |> Repo.preload(preloads)
  end

  def get_post_by_url_name!(url_name) do
    Repo.get_by!(Post, url_name: url_name)
  end

  def get_post_by_id_or_url_name(value) do
    Repo.one(
      from p in Post, where: p.id == ^value, or_where: p.url_name == ^value
    )
  end

  def get_featured_post() do
    Repo.one(
      from p in Post,
        where: p.state == :published,
        where: p.featured_post == true
    )
  end

  def count_published_posts() do
    Post
    |> where(state: :published)
    |> Repo.aggregate(:count, :id)
  end

  def list_posts(offset, limit) do
    # Preload associations - Ecto will batch load these efficiently
    Repo.all(
      from p in Post,
        where: p.state == :published,
        where: p.featured_post == false,
        order_by: [{:desc, :published_on}],
        limit: ^limit,
        offset: ^offset
    )
    |> Repo.preload([:author, :featured_image])
  end

  def list_posts(limit) do
    # Preload associations - Ecto will batch load these efficiently
    Repo.all(
      from p in Post,
        where: p.state == :published,
        where: p.featured_post == false,
        order_by: [{:desc, :published_on}],
        limit: ^limit
    )
    |> Repo.preload([:author, :featured_image])
  end

  def list_posts_paginated(params, opts \\ []) do
    opts = normalize_list_posts_opts(opts)
    date_from = Keyword.get(opts, :date_from, "")
    date_to = Keyword.get(opts, :date_to, "")
    search_term = Keyword.get(opts, :search_term)

    query =
      if search_term in [nil, ""] do
        Post
        |> where([p], p.state not in [:deleted])
        |> maybe_filter_posted_from(date_from)
        |> maybe_filter_posted_to(date_to)
        |> join(:left, [p], u in assoc(p, :author), as: :author)
        |> preload([author: o], author: o)
      else
        search_term = String.trim(search_term)
        fuzzy_search_posts(search_term)
        |> maybe_filter_posted_from(date_from)
        |> maybe_filter_posted_to(date_to)
      end

    query
    |> Flop.validate_and_run(params, for: Post)
  end

  defp normalize_list_posts_opts(search_term) when is_binary(search_term) or is_nil(search_term),
    do: [search_term: search_term]

  defp normalize_list_posts_opts(opts) when is_list(opts), do: opts

  defp maybe_filter_posted_from(query, ""), do: query

  defp maybe_filter_posted_from(query, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        where(query, [p], p.inserted_at >= ^datetime)

      _ ->
        query
    end
  end

  defp maybe_filter_posted_to(query, ""), do: query

  defp maybe_filter_posted_to(query, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
        where(query, [p], p.inserted_at <= ^datetime)

      _ ->
        query
    end
  end

  defp fuzzy_search_posts(search_term) do
    search_like = "%#{search_term}%"

    from(p in Post,
      left_join: u in assoc(p, :author),
      as: :author,
      where:
        p.state not in [:deleted] and
          (ilike(p.title, ^search_like) or ilike(coalesce(p.preview_text, ""), ^search_like) or
             (not is_nil(u.id) and
                (ilike(coalesce(u.first_name, ""), ^search_like) or
                   ilike(coalesce(u.last_name, ""), ^search_like) or
                   ilike(
                     fragment("coalesce(?, '') || ' ' || coalesce(?, '')", u.first_name, u.last_name),
                     ^search_like
                   )))),
      preload: [author: u]
    )
  end

  def update_post(post, params, %User{} = current_user, opts \\ []) do
    with :ok <- Policy.authorize(:post_update, current_user, post) do
      params = maybe_set_board_position_at_publish(post, params)
      post |> Post.update_post_changeset(params, opts) |> Repo.update()
    end
  end

  defp maybe_set_board_position_at_publish(post, params) do
    new_state = Map.get(params, "state") || Map.get(params, :state)

    going_published =
      new_state in ["published", :published] && post.state != :published

    already_set =
      Map.has_key?(params, "board_position_at_publish") ||
        Map.has_key?(params, :board_position_at_publish)

    if going_published && !already_set do
      post = Repo.preload(post, :author)
      position = post.author && post.author.board_position
      position_str = if position, do: to_string(position), else: nil

      # Use same key type as params so Ecto.Changeset.cast does not get mixed keys
      key =
        if Map.has_key?(params, :state),
          do: :board_position_at_publish,
          else: "board_position_at_publish"

      Map.put(params, key, position_str)
    else
      params
    end
  end

  def create_post(params, %User{} = current_user) do
    with :ok <- Policy.authorize(:post_create, current_user) do
      new_params = Map.put(params, "user_id", current_user.id)
      Post.new_post_changeset(%Post{}, new_params) |> Repo.insert()
    end
  end

  def get_comment!(comment_id, preloads \\ []) do
    Repo.one(
      from c in Comment,
        where: c.id == ^comment_id
    )
    |> Repo.preload(preloads)
  end

  def get_comments_for_post(post_id, preloads \\ []) do
    Repo.all(
      from c in Comment,
        where: c.post_id == ^post_id,
        order_by: [{:desc, :inserted_at}]
    )
    |> Repo.preload(preloads)
  end

  @doc """
  Gets the latest comments across all posts with author and post information.
  """
  def get_latest_comments(limit \\ 5) do
    Repo.all(
      from c in Comment,
        join: p in Post,
        on: c.post_id == p.id,
        where: p.state == :published,
        preload: [:author, post: [:author]],
        order_by: [{:desc, c.inserted_at}],
        limit: ^limit
    )
  end

  def sort_comments_for_render(comments) do
    replies =
      Enum.reduce(comments, %{}, fn entry, acc ->
        case entry.comment_id do
          nil ->
            acc

          value ->
            current = Map.get(acc, value, [])
            Map.put(acc, value, [entry | current])
        end
      end)

    Enum.reduce(comments, [], fn entry, acc ->
      case entry.comment_id do
        nil ->
          acc ++ [entry | Map.get(replies, entry.id, [])]

        _ ->
          acc
      end
    end)
  end

  def get_insert_index_for_comment(%Comment{comment_id: nil}), do: 0

  def get_insert_index_for_comment(%Comment{} = new_comment) do
    reply_to_id = new_comment.comment_id
    reply_counts = reply_counts(new_comment.post_id)

    root_comments_before =
      top_level_comments_before(reply_to_id, new_comment.post_id)

    Enum.reduce(reply_counts, 0, fn [c_id, reply_count], acc ->
      if c_id > reply_to_id do
        acc + reply_count
      else
        acc
      end
    end) + root_comments_before + 1
  end

  defp reply_counts(post_id) do
    Repo.all(
      from c in Comment,
        select: [c.comment_id, count(c.comment_id)],
        where: c.post_id == ^post_id,
        where: not is_nil(c.comment_id),
        group_by: c.comment_id,
        order_by: [{:desc, c.comment_id}]
    )
  end

  defp top_level_comments_before(comment_id, post_id) do
    Repo.one(
      from c in Comment,
        select: count(c.id),
        where: c.post_id == ^post_id,
        where: c.id > ^comment_id,
        where: is_nil(c.comment_id)
    )
  end

  def add_comment_to_post(params, %User{} = author) do
    corrected_params =
      params
      |> Map.put("user_id", author.id)

    Repo.transaction(add_comment_to_post_multi(corrected_params))
    |> case do
      {:ok, %{new_comment: comment}} ->
        {:ok, comment} |> broadcast_change("new_comment")

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  defp add_comment_to_post_multi(params) do
    changeset = Comment.new_comment_changeset(%Comment{}, params)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:post, fn _repo, _ ->
      get_post_with_lock(params["post_id"])
    end)
    |> Ecto.Multi.insert(:new_comment, fn _ ->
      changeset
    end)
    |> Ecto.Multi.update(:updated_post, fn %{post: post} ->
      post
      |> Post.update_comment_count_changeset(%{
        "comment_count" => post.comment_count + 1
      })
    end)
  end

  defp get_post_with_lock(post_id) do
    {:ok,
     from(p in Post,
       lock: fragment("FOR UPDATE OF ?", p),
       where: p.id == ^post_id
     )
     |> Repo.one()}
  end

  def count_posts_with_url_name(url_name) do
    search_term = "#{url_name}-%"

    Repo.one(
      from p in Post,
        select: count(p.id),
        where: p.url_name == ^url_name,
        or_where: ilike(p.url_name, ^search_term)
    )
  end

  def get_all_authors() do
    from(
      post in Post,
      left_join: user in assoc(post, :author),
      distinct: post.user_id,
      select: %{
        "user_id" => post.user_id,
        "author_first" => user.first_name,
        "author_last" => user.last_name
      },
      order_by: [{:desc, user.first_name}]
    )
    |> Repo.all()
    |> format_authors()
  end

  def post_topic(post_id) do
    "post-updates:#{post_id}"
  end

  defp broadcast_change({:ok, result}, event) do
    YscWeb.Endpoint.broadcast(post_topic(result.post_id), event, result)

    {:ok, result}
  end

  defp format_authors(result) do
    result
    |> Enum.reduce([], fn entry, acc ->
      [{name_format(entry), entry["user_id"]} | acc]
    end)
  end

  defp name_format(%{"author_first" => first, "author_last" => last}) do
    "#{String.capitalize(first)} #{String.downcase(last)}"
  end
end
