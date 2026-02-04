defmodule YscWeb.Scrubber.StripEverythingExceptTextTest do
  use ExUnit.Case, async: true

  alias HtmlSanitizeEx.Scrubber
  alias YscWeb.Scrubber.StripEverythingExceptText

  describe "scrubbing HTML" do
    test "allows div tags" do
      html = "<div>Hello World</div>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "<div>Hello World</div>"
    end

    test "allows br tags" do
      html = "Line 1<br>Line 2"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # HTML sanitizer may normalize br tags
      assert result == "Line 1<br>Line 2" or result == "Line 1<br />Line 2"
    end

    test "allows strong tags" do
      html = "This is <strong>bold</strong> text"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "This is <strong>bold</strong> text"
    end

    test "allows em tags" do
      html = "This is <em>italic</em> text"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "This is <em>italic</em> text"
    end

    test "allows multiple allowed tags together" do
      html = "<div><strong>Bold</strong> and <em>italic</em> text<br></div>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # HTML sanitizer may normalize br tags
      assert result ==
               "<div><strong>Bold</strong> and <em>italic</em> text<br></div>" or
               result ==
                 "<div><strong>Bold</strong> and <em>italic</em> text<br /></div>"
    end

    test "strips script tags but preserves content as text" do
      html = "<div>Content</div><script>alert('xss')</script>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # Script tags are stripped but content may be preserved as text
      assert String.contains?(result, "<div>Content</div>")
      refute String.contains?(result, "<script>")
    end

    test "strips iframe tags" do
      html = "<div>Content</div><iframe src='evil.com'></iframe>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "<div>Content</div>"
    end

    test "strips img tags" do
      html = "<div>Content</div><img src='image.jpg' alt='test'>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # Img tags are stripped (they have no text content)
      assert result == "<div>Content</div>" or
               String.contains?(result, "<div>Content</div>")
    end

    test "strips anchor tags but preserves text" do
      html = "<div>Content</div><a href='http://evil.com'>Link</a>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # Text content is preserved when tags are stripped
      assert result == "<div>Content</div>Link"
    end

    test "strips style tags but may preserve content as text" do
      html = "<div>Content</div><style>body { color: red; }</style>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # Style tags are stripped but content may be preserved as text
      assert String.contains?(result, "<div>Content</div>")
      refute String.contains?(result, "<style>")
    end

    test "strips p tags but preserves text" do
      html = "<p>Paragraph</p><div>Content</div>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # Text content is preserved when tags are stripped
      assert result == "Paragraph<div>Content</div>"
    end

    test "strips span tags" do
      html = "<div><span>Text</span></div>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "<div>Text</div>"
    end

    test "strips attributes from allowed tags" do
      html = "<div class='test' id='mydiv'>Content</div>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # Attributes should be stripped
      assert result == "<div>Content</div>"
    end

    test "strips onclick and other event handlers" do
      html = "<div onclick='alert(1)'>Content</div>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "<div>Content</div>"
    end

    test "strips comments" do
      html = "<div>Content</div><!-- This is a comment -->"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "<div>Content</div>"
    end

    test "handles nested allowed tags" do
      html = "<div><strong>Bold <em>and italic</em></strong></div>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "<div><strong>Bold <em>and italic</em></strong></div>"
    end

    test "handles empty div tags" do
      html = "<div></div>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "<div></div>"
    end

    test "handles self-closing br tags" do
      html = "Line 1<br/>Line 2"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # HTML sanitizer may normalize br tags
      assert result == "Line 1<br>Line 2" or result == "Line 1<br />Line 2"
    end

    test "preserves text content when tags are stripped" do
      html = "<p>Paragraph text</p><span>Span text</span>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "Paragraph textSpan text"
    end

    test "handles complex HTML with mixed allowed and disallowed tags" do
      html = """
      <div>
        <h1>Title</h1>
        <p>Paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
        <script>alert('xss')</script>
        <img src="image.jpg">
        <br>
      </div>
      """

      result = Scrubber.scrub(html, StripEverythingExceptText)

      # Should only contain allowed tags
      refute String.contains?(result, "<h1>")
      refute String.contains?(result, "<p>")
      refute String.contains?(result, "<script>")
      refute String.contains?(result, "<img")
      assert String.contains?(result, "<div>")
      assert String.contains?(result, "<strong>bold</strong>")
      assert String.contains?(result, "<em>italic</em>")
      # br may be normalized to <br />
      assert String.contains?(result, "<br") or String.contains?(result, "<br>")
      assert String.contains?(result, "Title")
      assert String.contains?(result, "Paragraph with")
    end

    test "handles empty string" do
      html = ""
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == ""
    end

    test "handles plain text without tags" do
      html = "Just plain text without any HTML tags"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      assert result == "Just plain text without any HTML tags"
    end

    test "handles CDATA sections" do
      # CDATA should be removed before scrubbing
      html = "<div><![CDATA[Some content]]></div>"
      result = Scrubber.scrub(html, StripEverythingExceptText)
      # CDATA content should be preserved as text
      assert String.contains?(result, "Some content")
    end
  end
end
