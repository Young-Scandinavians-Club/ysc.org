defmodule Ysc.Html.LinksTest do
  use ExUnit.Case, async: true

  alias Ysc.Html.Links

  describe "open_in_new_tab/1" do
    test "returns empty string for nil or empty input" do
      assert Links.open_in_new_tab(nil) == ""
      assert Links.open_in_new_tab("") == ""
    end

    test "adds target and rel to links with href" do
      html = ~s|<p><a href="https://example.com">Example</a></p>|
      out = Links.open_in_new_tab(html)

      assert out =~ ~s|href="https://example.com"|
      assert out =~ ~s|target="_blank"|
      assert out =~ ~s|rel="noopener noreferrer"|
    end

    test "overwrites existing target and rel" do
      html =
        ~s|<a href="https://example.com" target="_self" rel="nofollow">x</a>|

      out = Links.open_in_new_tab(html)

      assert out =~ ~s|target="_blank"|
      assert out =~ ~s|rel="noopener noreferrer"|
      refute out =~ ~s|target="_self"|
      refute out =~ ~s|rel="nofollow"|
    end

    test "leaves named anchors without href unchanged" do
      html = ~s|<a name="section">Heading</a>|
      out = Links.open_in_new_tab(html)

      assert out =~ ~s|name="section"|
      refute out =~ "target="
    end

    test "preserves surrounding markup" do
      html = "<p>Before <strong>bold</strong> after</p>"
      assert Links.open_in_new_tab(html) =~ "<strong>bold</strong>"
    end
  end
end
