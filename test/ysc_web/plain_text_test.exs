defmodule YscWeb.PlainTextTest do
  use ExUnit.Case, async: true

  alias Ysc.Posts.Post
  alias YscWeb.PlainText

  describe "from_html/1" do
    test "strips tags and decodes entities" do
      assert PlainText.from_html("<p>Hello <strong>world</strong></p>") ==
               "Hello world"

      assert PlainText.from_html("At Tupper &amp; Reed") == "At Tupper & Reed"
    end

    test "preserves line breaks from br and block elements" do
      assert PlainText.from_html("Line 1<br>Line 2") == "Line 1\nLine 2"
      assert PlainText.from_html("Line 1<br />Line 2") == "Line 1\nLine 2"

      assert PlainText.from_html("<p>First</p><p>Second</p>") ==
               "First\nSecond"
    end

    test "strips formatting tags without escaping artifacts" do
      html =
        "This is a test event<strong>Hkk</strong><div></div>Happy python code<div><br /></div>"

      result = PlainText.from_html(html)

      assert result =~ "This is a test eventHkk"
      assert result =~ "Happy python code"
      refute result =~ "<strong>"
      refute result =~ "&lt;"
      refute result =~ "<div>"
    end

    test "returns empty string for nil and empty input" do
      assert PlainText.from_html(nil) == ""
      assert PlainText.from_html("") == ""
    end
  end

  describe "from_post/1" do
    test "prefers preview_text over raw_body" do
      post = %Post{
        preview_text: "<p>Preview</p>",
        raw_body: "<p>Body</p>"
      }

      assert PlainText.from_post(post) == "Preview"
    end

    test "falls back to raw_body when preview_text is nil" do
      post = %Post{
        preview_text: nil,
        raw_body: "<p>From body</p>"
      }

      assert PlainText.from_post(post) == "From body"
    end

    test "returns empty string for whitespace-only preview with no body" do
      post = %{preview_text: "   \n  ", raw_body: nil}
      assert PlainText.from_post(post) == ""
    end
  end
end
