defmodule Ysc.Posts.Slug do
  @moduledoc """
  Generates URL slugs for posts from titles.
  """

  alias Ysc.Posts

  @untitled_slug "new-untitled-post"
  @default_title "New Untitled Post"

  @doc """
  Default title shown in the editor for a new, unsaved post.
  """
  def default_title, do: @default_title

  @doc """
  True when the title is nil, empty, or only whitespace.
  """
  def blank_title?(title) when is_binary(title) do
    String.trim(title) == ""
  end

  def blank_title?(_), do: true

  @doc """
  Returns `default_title/0` when the title is blank, otherwise the trimmed title.
  """
  def title_or_default(nil), do: @default_title

  def title_or_default(title) when is_binary(title) do
    if String.trim(title) == "", do: @default_title, else: title
  end

  def title_or_default(_), do: @default_title

  @doc """
  Slugifies a post title. Empty titles become `"new-untitled-post"`.
  Does not check uniqueness; use `unique/1` before persisting.
  """
  def from_title(title) when is_binary(title) do
    title
    |> String.downcase()
    |> then(&Regex.replace(~r/\s+/u, &1, "-"))
    |> then(&Regex.replace(~r/[^0-9\-a-z]/u, &1, ""))
    |> maybe_replace_empty()
  end

  def from_title(_), do: @untitled_slug

  @doc """
  Appends `-N` when `url_name` is already taken.
  """
  def unique(url_name) do
    case Posts.count_posts_with_url_name(url_name) do
      0 -> url_name
      n -> "#{url_name}-#{n + 1}"
    end
  end

  @doc """
  Slugifies a title and ensures uniqueness in the database.
  """
  def from_title_unique(title) do
    title |> from_title() |> unique()
  end

  defp maybe_replace_empty(""), do: @untitled_slug
  defp maybe_replace_empty(value), do: value
end
