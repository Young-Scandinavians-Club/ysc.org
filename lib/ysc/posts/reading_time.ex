defmodule Ysc.Posts.ReadingTime do
  @moduledoc """
  Estimates article reading time from post HTML or plain text.

  Used by the news index, news cards, and home-page news teasers so every
  surface uses the same 225 words-per-minute estimate.
  """

  @words_per_minute 225

  @doc """
  Returns estimated reading time in minutes (minimum 1).

  Prefers `rendered_body`, then `raw_body`, then `preview_text`. HTML tags
  and entities are stripped before counting words.
  """
  def minutes(post) when is_map(post) do
    cond do
      present?(Map.get(post, :rendered_body)) ->
        minutes_from_html(Map.get(post, :rendered_body))

      present?(Map.get(post, :raw_body)) ->
        minutes_from_html(Map.get(post, :raw_body))

      present?(Map.get(post, :preview_text)) ->
        minutes_from_html(Map.get(post, :preview_text))

      true ->
        1
    end
  end

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_), do: false

  defp minutes_from_html(html) do
    html
    |> count_words_in_html()
    |> from_word_count()
  end

  defp count_words_in_html(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/&[a-z]+;/i, " ")
    |> String.replace(~r/&#\d+;/, " ")
    |> count_words_in_text()
  end

  defp count_words_in_text(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  defp from_word_count(word_count) when word_count <= 0, do: 1

  defp from_word_count(word_count) do
    max(1, round(word_count / @words_per_minute))
  end
end
