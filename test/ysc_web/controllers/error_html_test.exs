defmodule YscWeb.ErrorHTMLTest do
  use YscWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html" do
    html = render_to_string(YscWeb.ErrorHTML, "404", "html", [])
    assert html =~ "404"
    assert html =~ "Page not found"
    assert html =~ ~s(id="error-404-home-logo")
    assert html =~ "bg-[#fcf9ec]"
    assert html =~ "min-h-screen"
    assert html =~ "max-w-5xl"
    assert html =~ "Go back home"
    assert html =~ ~s(src="/images/lost_tomte.webp")
    assert html =~ ~s(alt="404 Lost Tomte")
  end

  test "renders 500.html" do
    html = render_to_string(YscWeb.ErrorHTML, "500", "html", [])
    assert html =~ "500"
    assert html =~ "Something went wrong"
    assert html =~ ~s(id="error-500-home-logo")
    assert html =~ "bg-[#f9efdf]"
    assert html =~ "min-h-screen"
    assert html =~ "max-w-5xl"
    assert html =~ "Go back home"
    assert html =~ ~s(src="/images/404_fika.webp")
    assert html =~ ~s(alt="500 Fika")
  end

  test "404 response includes document title", %{conn: conn} do
    conn = get(conn, "/this-route-does-not-exist-for-error-title-test")
    html = html_response(conn, 404)
    document = LazyHTML.from_document(html)
    title = LazyHTML.query(document, "title")

    assert LazyHTML.text(title) |> String.trim() ==
             "Page not found · Young Scandinavians Club"
  end

  test "error layout titles by status" do
    assert YscWeb.Layouts.error_page_title(%{status: 400}) == "Bad request"
    assert YscWeb.Layouts.error_page_title(%{status: 403}) == "Access denied"
    assert YscWeb.Layouts.error_page_title(%{status: 404}) == "Page not found"

    assert YscWeb.Layouts.error_page_title(%{status: 500}) ==
             "Something went wrong"

    assert YscWeb.Layouts.error_page_title(%{
             conn: %Plug.Conn{status: 404}
           }) == "Page not found"

    assert YscWeb.Layouts.error_page_title(%{}) == "Error"
    assert YscWeb.Layouts.error_page_title(%{page_title: "Custom"}) == "Custom"
  end

  test "render_page/2 assigns status-derived page titles", %{conn: conn} do
    for {template, status, title} <- [
          {:"400", 400, "Bad request"},
          {:"403", 403, "Access denied"},
          {:"404", 404, "Page not found"},
          {:"500", 500, "Something went wrong"}
        ] do
      rendered =
        conn
        |> Plug.Conn.fetch_query_params()
        |> Phoenix.Controller.put_format("html")
        |> YscWeb.ErrorHTML.render_page(template)

      assert rendered.assigns.page_title == title
      assert rendered.status == status
    end
  end
end
