defmodule Ysc.AdminHelp.KnowledgeBase do
  @moduledoc """
  Markdown knowledge base for the admin help assistant.

  Documents live in `priv/admin_help_kb/*.md` with a small front-matter block:

      ---
      title: Posts & news articles
      summary: Editor, drafts, publishing, pinning, comments.
      ---

      # Document body…

  The assistant is shown a lightweight index (slug + title + summary) and can
  request full documents on the fly, so large reference content never pollutes
  the context window unless it is actually relevant.
  """

  @doc "Directory containing the knowledge base markdown files."
  def dir do
    Application.app_dir(:ysc, "priv/admin_help_kb")
  end

  @doc """
  Lists all documents as `%{slug: String.t(), title: String.t(), summary: String.t()}`,
  sorted by slug. Slug is the filename without extension.
  """
  def index do
    case File.ls(dir()) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.sort()
        |> Enum.map(&entry_for_file/1)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  @doc """
  Compact index for an LLM system prompt — one line per document.

  When `role` is set, omits reference docs not in that role's audience.
  """
  def index_for_llm(role \\ nil) do
    index()
    |> Enum.filter(&doc_visible_to_role?(&1, role))
    |> Enum.map_join("\n", fn %{slug: slug, title: title, summary: summary} ->
      "- #{slug}: #{title} — #{summary}"
    end)
  end

  @doc "Whether a knowledge-base document is visible to the given staff role."
  def visible_to_role?(slug, role) when is_binary(slug) do
    case Enum.find(index(), &(&1.slug == slug)) do
      nil -> false
      entry -> doc_visible_to_role?(entry, role)
    end
  end

  def visible_to_role?(_slug, _role), do: false

  @doc """
  Fetches a document body (front matter removed) by slug.

  Returns `{:ok, content}` or `:error`. Slugs are restricted to
  `[a-z0-9-]` so arbitrary paths can never be read.
  """
  def fetch(slug) when is_binary(slug) do
    if valid_slug?(slug) do
      path = Path.join(dir(), slug <> ".md")

      case File.read(path) do
        {:ok, raw} ->
          {_meta, body} = split_front_matter(raw)
          {:ok, String.trim(body)}

        {:error, _} ->
          :error
      end
    else
      :error
    end
  end

  def fetch(_), do: :error

  @doc "Whether a slug refers to an existing document."
  def valid_doc?(slug), do: match?({:ok, _}, fetch(slug))

  @doc """
  Fetches several documents at once, skipping unknown slugs, capped at `limit`.

  Returns a list of `{slug, content}` tuples.
  """
  def fetch_many(slugs, limit \\ 3) when is_list(slugs) do
    slugs
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.take(limit)
    |> Enum.flat_map(fn slug ->
      case fetch(slug) do
        {:ok, content} -> [{slug, content}]
        :error -> []
      end
    end)
  end

  defp entry_for_file(file) do
    slug = Path.rootname(file)

    with true <- valid_slug?(slug),
         {:ok, raw} <- File.read(Path.join(dir(), file)) do
      {meta, _body} = split_front_matter(raw)

      %{
        slug: slug,
        title: Map.get(meta, "title", slug),
        summary: Map.get(meta, "summary", ""),
        audience: parse_audience(Map.get(meta, "audience"))
      }
    else
      _ -> nil
    end
  end

  defp valid_slug?(slug) do
    Regex.match?(~r/^[a-z0-9][a-z0-9-]*$/, slug)
  end

  # Parses the minimal `key: value` front matter block delimited by `---` lines.
  defp split_front_matter("---\n" <> rest) do
    case String.split(rest, "\n---", parts: 2) do
      [front, body] ->
        meta =
          front
          |> String.split("\n", trim: true)
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, ":", parts: 2) do
              [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
              _ -> acc
            end
          end)

        {meta, body}

      _ ->
        {%{}, rest}
    end
  end

  defp split_front_matter(raw), do: {%{}, raw}

  defp parse_audience(nil), do: [:admin, :volunteer]

  defp parse_audience(audience) when is_binary(audience) do
    audience
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn
      "admin" -> :admin
      "volunteer" -> :volunteer
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> [:admin, :volunteer]
      roles -> roles
    end
  end

  defp doc_visible_to_role?(_entry, nil), do: true

  defp doc_visible_to_role?(%{audience: audience}, role)
       when role in [:admin, :volunteer] do
    role in audience
  end

  defp doc_visible_to_role?(_, _), do: true
end
