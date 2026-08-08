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
    assert html =~ "Something went wrong"
  end

  test "404 response includes document title", %{conn: conn} do
    conn = get(conn, "/this-route-does-not-exist-for-error-title-test")
    html = html_response(conn, 404)

    assert html =~
             ~r/<title>\s*Page not found · Young Scandinavians Club\s*<\/title>/
  end

  test "error layout titles by status" do
    assert YscWeb.Layouts.error_page_title(%{status: 404}) == "Page not found"

    assert YscWeb.Layouts.error_page_title(%{status: 500}) ==
             "Something went wrong"

    assert YscWeb.Layouts.error_page_title(%{page_title: "Custom"}) == "Custom"
  end
end
