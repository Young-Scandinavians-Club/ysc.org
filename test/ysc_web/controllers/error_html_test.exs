defmodule YscWeb.ErrorHTMLTest do
  use YscWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html" do
    html = render_to_string(YscWeb.ErrorHTML, "404", "html", [])
    assert html =~ "404"
    assert html =~ "Page not found"
  end

  test "renders 500.html" do
    html = render_to_string(YscWeb.ErrorHTML, "500", "html", [])
    assert html =~ "500"
    assert html =~ "Internal Server Error"
  end
end
