defmodule Ysc.WpMigration.HtmlTransformerTest do
  use ExUnit.Case, async: true

  alias Ysc.WpMigration.HtmlTransformer

  test "rewrites unquoted wp-image attributes to migration media URLs" do
    html =
      "<img src=https://ysc.org/wp-content/uploads/2022/12/IMG_4064-1024x768.jpeg alt= class=wp-image-45237/>"

    url_map = %{"45237" => "https://assets.ysc.org/migration/45237/file.jpeg"}

    out = HtmlTransformer.wp_to_trix(html, url_map)

    assert out =~ "https://assets.ysc.org/migration/45237/file.jpeg"
    refute out =~ "wp-content/uploads"
  end

  test "rewrites unquoted multi-word class attributes with wp-image id" do
    html =
      "<img src=https://ysc.org/wp-content/uploads/2017/10/01-1024x768.jpg alt= width=1024 height=768 class=alignnone wp-image-7161 size-large>"

    url_map = %{"7161" => "https://assets.ysc.org/migration/7161/file.jpg"}

    out = HtmlTransformer.wp_to_trix(html, url_map)

    assert out =~ "https://assets.ysc.org/migration/7161/file.jpg"
    refute out =~ "wp-content/uploads"
  end
end
