defmodule YscWeb.SitemapController do
  use YscWeb, :controller

  alias Ysc.Sitemap

  def index(conn, _params) do
    xml = Sitemap.generate()

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
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
    |> send_resp(200, String.trim(content))
  end
end
