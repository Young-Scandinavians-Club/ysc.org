defmodule Ysc.Html.TrixTest do
  use ExUnit.Case, async: true

  alias Ysc.Html.Trix

  describe "scrub/1" do
    test "matches HtmlSanitizeEx.Scrubber.scrub/2 with TrixScrubber" do
      html = """
      <p onclick="evil()">Hello <strong>world</strong></p>
      <script>alert(1)</script>
      <a href="https://example.com">ok</a>
      <a href="javascript:alert(1)">bad</a>
      """

      assert Trix.scrub(html) ==
               HtmlSanitizeEx.Scrubber.scrub(html, Ysc.TrixScrubber)
    end

    test "allows Trix formatting and strips scripts" do
      html = "<p>Hello <strong>world</strong></p><script>alert(1)</script>"
      out = Trix.scrub(html)

      assert out =~ "<p>"
      assert out =~ "<strong>"
      assert out =~ "world"
      refute out =~ "<script"
    end

    test "returns empty string for empty input" do
      assert Trix.scrub("") == ""
    end
  end
end
