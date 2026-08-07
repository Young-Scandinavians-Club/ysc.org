defmodule YscWeb.SitemapControllerTest do
  use YscWeb.ConnCase, async: true

  describe "GET /sitemap.xml" do
    test "returns the sitemap as application/xml", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")

      assert response(conn, 200) =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert hd(get_resp_header(conn, "content-type")) =~ "application/xml"
      assert response(conn, 200) =~ "<urlset"
    end
  end

  describe "GET /robots.txt" do
    test "returns robots.txt as text/plain with disallowed paths and sitemap link",
         %{
           conn: conn
         } do
      conn = get(conn, ~p"/robots.txt")

      body = response(conn, 200)

      assert hd(get_resp_header(conn, "content-type")) =~ "text/plain"
      assert body =~ "User-agent: *"
      assert body =~ "Disallow: /admin/"
      assert body =~ "Disallow: /dev/"
      assert body =~ "Sitemap: #{YscWeb.Endpoint.url()}/sitemap.xml"
    end
  end
end
