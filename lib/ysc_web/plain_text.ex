defmodule YscWeb.PlainText do
  @moduledoc """
  Converts HTML to plain text for safe display in templates, feeds, and emails.

  Strips all markup while preserving line breaks from `<br>` and block elements,
  and decodes HTML entities.
  """

  alias Ysc.Posts.Post

  @block_close_tags ~r/<\/(p|div|h[1-6]|li|tr|blockquote)>/i
  @br_tags ~r/<br\s*\/?>/i

  @doc """
  Converts HTML to plain text.

  Returns an empty string for nil or empty input.
  """
  def from_html(nil), do: ""
  def from_html(""), do: ""

  def from_html(html) when is_binary(html) do
    html
    |> normalize_line_breaks()
    |> HtmlSanitizeEx.strip_tags()
    |> decode_html_entities()
    |> String.trim()
  end

  @doc """
  Normalizes plain text for clamped preview display.

  Trims leading and trailing whitespace and returns `nil` for blank input.
  """
  def normalize_preview(nil), do: nil
  def normalize_preview(""), do: nil

  def normalize_preview(text) when is_binary(text) do
    case from_html(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  Plain-text preview for a post, preferring `preview_text` over `raw_body`.
  """
  def from_post(%Post{preview_text: preview_text, raw_body: raw_body}) do
    cond do
      present?(preview_text) -> from_html(preview_text)
      present?(raw_body) -> from_html(raw_body)
      true -> ""
    end
  end

  def from_post(%{preview_text: preview_text, raw_body: raw_body}) do
    cond do
      present?(preview_text) -> from_html(preview_text)
      present?(raw_body) -> from_html(raw_body)
      true -> ""
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp normalize_line_breaks(html) do
    html
    |> String.replace(@br_tags, "\n")
    |> String.replace(@block_close_tags, "\n")
  end

  defp decode_html_entities(text) do
    case Floki.parse_fragment(text) do
      {:ok, document} ->
        Floki.text(document)

      {:error, _} ->
        case Floki.parse_fragment("<span>#{text}</span>") do
          {:ok, document} -> Floki.text(document)
          {:error, _} -> text
        end
    end
  end
end
