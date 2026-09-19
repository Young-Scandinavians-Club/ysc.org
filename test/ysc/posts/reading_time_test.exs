defmodule Ysc.Posts.ReadingTimeTest do
  use ExUnit.Case, async: true

  alias Ysc.Posts.ReadingTime

  describe "minutes/1" do
    test "returns 1 when no body fields are present" do
      assert ReadingTime.minutes(%{}) == 1

      assert ReadingTime.minutes(%{
               rendered_body: nil,
               raw_body: nil,
               preview_text: nil
             }) == 1

      assert ReadingTime.minutes(%{
               rendered_body: "",
               raw_body: "",
               preview_text: ""
             }) == 1
    end

    test "counts words in rendered_body after stripping HTML tags" do
      html = "<p>" <> String.duplicate("word ", 225) <> "</p>"

      assert ReadingTime.minutes(%{rendered_body: html}) == 1
    end

    test "rounds to the nearest minute at 225 words per minute" do
      html = "<p>" <> String.duplicate("word ", 338) <> "</p>"

      assert ReadingTime.minutes(%{rendered_body: html}) == 2
    end

    test "does not count HTML tags or entities as words" do
      html = "<p>Hello&nbsp;world</p><div>again</div>"

      assert ReadingTime.minutes(%{rendered_body: html}) == 1
    end

    test "prefers rendered_body over raw_body and preview_text" do
      rendered = "<p>" <> String.duplicate("word ", 450) <> "</p>"

      assert ReadingTime.minutes(%{
               rendered_body: rendered,
               raw_body: "short",
               preview_text: "also short"
             }) == 2
    end

    test "falls back to raw_body when rendered_body is blank" do
      raw = String.duplicate("word ", 225)

      assert ReadingTime.minutes(%{
               rendered_body: "",
               raw_body: raw,
               preview_text: "preview"
             }) == 1
    end

    test "falls back to preview_text when bodies are blank" do
      preview = String.duplicate("word ", 450)

      assert ReadingTime.minutes(%{
               rendered_body: nil,
               raw_body: "",
               preview_text: preview
             }) == 2
    end

    test "returns 1 for whitespace-only content after stripping tags" do
      assert ReadingTime.minutes(%{rendered_body: "<p>   </p>"}) == 1
    end
  end
end
