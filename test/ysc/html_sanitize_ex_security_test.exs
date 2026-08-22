defmodule Ysc.HtmlSanitizeExSecurityTest do
  use ExUnit.Case, async: true

  alias HtmlSanitizeEx.Scrubber

  @nested_style ~s|<p>safe</p><style><img src="https://evil.example/x.png" alt="x"><p>leak</p></style>|
  @meta_refresh ~s|<p>ok</p><meta http-equiv="refresh" content="0;url=https://evil.example">|
  @object_data ~s|<p>ok</p><object data="javascript:alert(1)"></object>|

  describe "1.5.5 CSS.scrub nested tags" do
    test "returns empty string for nil" do
      assert Scrubber.CSS.scrub(nil) == ""
    end

    test "returns empty string when the parser passes nested tags instead of CSS text" do
      nested = [
        {"p", [], ["color: red"]},
        {"img", [{"src", "https://evil.example/x.png"}], []}
      ]

      assert Scrubber.CSS.scrub(nested) == ""
    end

    test "still scrubs binary CSS and strips @import" do
      out =
        Scrubber.CSS.scrub("@import url(//attacker.example/x.css); color: red;")

      refute out =~ "import"
      refute out =~ "attacker"
    end
  end

  describe "production scrubbers with nested tags in style" do
    test "TrixScrubber does not keep a style tag" do
      out = Scrubber.scrub(@nested_style, Ysc.TrixScrubber)
      refute out =~ "<style"
      assert out =~ "safe"
    end

    test "BasicHTML does not keep a style tag" do
      out = Scrubber.scrub(@nested_style, Scrubber.BasicHTML)
      refute out =~ "<style"
      assert out =~ "safe"
    end

    test "strip_tags does not keep a style tag" do
      out = HtmlSanitizeEx.strip_tags(@nested_style)
      refute out =~ "<style"
      assert out =~ "safe"
    end

    test "PlainText.from_html does not keep a style tag" do
      out = YscWeb.PlainText.from_html(@nested_style)
      refute out =~ "<style"
      assert out =~ "safe"
    end
  end

  describe "production scrubbers reject HTML5-only vectors" do
    test "TrixScrubber strips meta refresh and javascript object data" do
      html = @meta_refresh <> @object_data
      out = Scrubber.scrub(html, Ysc.TrixScrubber)
      refute out =~ "<meta"
      refute out =~ "refresh"
      refute out =~ "<object"
      refute out =~ "javascript"
      assert out =~ "ok"
    end

    test "BasicHTML strips meta refresh and javascript object data" do
      html = @meta_refresh <> @object_data
      out = Scrubber.scrub(html, Scrubber.BasicHTML)
      refute out =~ "<meta"
      refute out =~ "refresh"
      refute out =~ "<object"
      refute out =~ "javascript"
      assert out =~ "ok"
    end

    test "strip_tags strips meta refresh and object markup" do
      html = @meta_refresh <> @object_data
      out = HtmlSanitizeEx.strip_tags(html)
      refute out =~ "<meta"
      refute out =~ "<object"
      refute out =~ "javascript"
      assert out =~ "ok"
    end
  end

  describe "HTML5 1.5.5 hardening" do
    test "nested tags inside style are not treated as CSS text" do
      html = ~s|<style><p>color: red</p></style>|
      out = HtmlSanitizeEx.html5(html)
      refute out =~ "color: red"
    end

    test "meta refresh is stripped" do
      out = HtmlSanitizeEx.html5(@meta_refresh)
      refute out =~ "refresh"
      refute out =~ "evil.example"
      assert out =~ "ok"
    end

    test "javascript: object data is stripped" do
      out = HtmlSanitizeEx.html5(@object_data)
      refute out =~ "javascript"
      assert out =~ "ok"
    end
  end
end
