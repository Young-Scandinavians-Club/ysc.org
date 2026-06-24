defmodule Ysc.TrixScrubberTest do
  use ExUnit.Case, async: true

  alias HtmlSanitizeEx.Scrubber

  defp scrub(html), do: Scrubber.scrub(html, Ysc.TrixScrubber)

  describe "scrub/1" do
    test "allows basic formatting and structure" do
      html = "<p>Hello <strong>world</strong></p><ul><li>one</li></ul>"
      assert scrub(html) =~ "<p>"
      assert scrub(html) =~ "<strong>"
      assert scrub(html) =~ "<ul>"
    end

    test "allows links with http, https, and mailto schemes" do
      html =
        "<p><a href=\"https://example.com\">x</a> <a href=\"mailto:a@b.co\">m</a></p>"

      out = scrub(html)
      assert out =~ "href=\"https://example.com\""
      assert out =~ "href=\"mailto:a@b.co\""
    end

    test "strips dangerous javascript: URLs" do
      html = ~s|<a href="javascript:alert(1)">bad</a>|
      refute scrub(html) =~ "javascript"
    end

    test "strips script tags and event handlers" do
      html =
        "<p onclick=\"evil()\">x</p><script>alert(1)</script><p>ok</p>"

      out = scrub(html)
      refute out =~ "<script"
      refute out =~ "onclick"
      assert out =~ "ok"
    end

    test "allows img with safe src and dimensions" do
      html =
        "<figure class=\"attachment\"><img src=\"https://cdn.example.com/a.png\" alt=\"A\" width=\"100\" height=\"80\" /></figure>"

      out = scrub(html)
      assert out =~ "src=\"https://cdn.example.com/a.png\""
      assert out =~ "figure"
      assert out =~ "img"
    end

    test "allows Trix figure data attributes" do
      html =
        "<figure data-trix-attachment=\"{}\" data-trix-content-type=\"image/png\" data-trix-attributes=\"{}\"><figcaption class=\"cap\">Caption</figcaption></figure>"

      out = scrub(html)
      assert out =~ "data-trix-attachment"
      assert out =~ "figcaption"
    end

    test "strips style attributes and trix-specific noise from disallowed contexts" do
      html = "<p style=\"color:red\">x</p>"
      refute scrub(html) =~ "style="
    end

    test "allows tables" do
      html =
        "<table><thead><tr><th>H</th></tr></thead><tbody><tr><td>c</td></tr></tbody></table>"

      out = scrub(html)
      assert out =~ "<table>"
      assert out =~ "<td>"
    end

    test "returns empty string for empty input" do
      assert scrub("") == ""
    end

    test "does not crash on truncated processing-instruction marker" do
      assert scrub("<?") == "&lt;?"
      assert scrub("<p>Hello <?</p>") =~ "Hello"
    end

    test "allows blockquote and code" do
      html = "<blockquote><p>Q</p></blockquote><pre><code>x</code></pre>"
      out = scrub(html)
      assert out =~ "blockquote"
      assert out =~ "code"
    end

    test "strips non-http(s) schemes on links and images" do
      html =
        ~s|<a href="ftp://files.example.com/a">f</a><img src="data:image/png;base64,xx" alt="x"/>|

      out = scrub(html)
      refute out =~ "ftp:"
      refute out =~ "data:image"
    end

    test "allows ordered lists and horizontal rules" do
      html = "<ol><li>one</li></ol><hr />"
      out = scrub(html)
      assert out =~ "<ol>"
      assert out =~ "<hr"
    end

    test "allows headings and inline formatting tags" do
      html =
        "<h4>H4</h4><h5>H5</h5><h6>H6</h6><del>gone</del><u>u</u><i>i</i><span>sp</span>"

      out = scrub(html)
      assert out =~ "<h4>"
      assert out =~ "<del>"
      assert out =~ "<u>"
      assert out =~ "<span>"
    end

    test "allows links with name and title attributes" do
      html = ~s|<a href="https://example.com" name="n" title="t">x</a>|
      out = scrub(html)
      assert out =~ "name=\"n\""
      assert out =~ "title=\"t\""
    end

    test "strips unknown attributes on allowed tags" do
      html = ~s|<p id="x" data-x="1">x</p>|
      out = scrub(html)
      refute out =~ "data-x"
    end

    test "allows figure with nested anchor for image attachments" do
      html =
        "<figure class=\"attachment\"><a href=\"https://cdn.example.com/a.png\"><img src=\"https://cdn.example.com/a.png\" alt=\"\"/></a></figure>"

      out = scrub(html)
      assert out =~ "<figure"
      assert out =~ "href=\"https://cdn.example.com/a.png\""
    end
  end
end
