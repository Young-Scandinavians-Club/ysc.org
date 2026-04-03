defmodule YscWeb.SitemapController do
  use YscWeb, :controller

  alias Ysc.Sitemap

  def index(conn, _params) do
    xml = Sitemap.generate()

    conn
    |> put_resp_content_type("application/xml")
    |> text(xml)
  end

  def robots(conn, _params) do
    base = YscWeb.Endpoint.url()

    content = """
    User-agent: *
    Disallow: /admin/
    Disallow: /expensereport
    Disallow: /users/
    Disallow: /onboarding
    Disallow: /billing/
    Disallow: /webhooks/
    Disallow: /auth/
    Disallow: /dev/

    Sitemap: #{base}/sitemap.xml
    """

    conn
    |> put_resp_content_type("text/plain")
    |> text(String.trim(content))
  end
end
