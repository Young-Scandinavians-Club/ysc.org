defmodule YscWeb.Plugs.SecurityHeadersTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias YscWeb.Plugs.SecurityHeaders

  setup do
    old_env = Application.get_env(:ysc, :environment)
    old_endpoint = Application.get_env(:ysc, YscWeb.Endpoint)
    old_s3_base = Application.get_env(:ysc, :s3_base_url)

    on_exit(fn ->
      if is_nil(old_env),
        do: Application.delete_env(:ysc, :environment),
        else: Application.put_env(:ysc, :environment, old_env)

      if is_nil(old_endpoint),
        do: Application.delete_env(:ysc, YscWeb.Endpoint),
        else: Application.put_env(:ysc, YscWeb.Endpoint, old_endpoint)

      if is_nil(old_s3_base),
        do: Application.delete_env(:ysc, :s3_base_url),
        else: Application.put_env(:ysc, :s3_base_url, old_s3_base)
    end)

    :ok
  end

  test "sets CSP header including nonce" do
    Application.put_env(:ysc, :environment, :dev)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: true)

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "abc123")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    assert String.contains?(csp, "'nonce-abc123'")
    assert String.contains?(csp, "script-src")
    assert String.contains?(csp, "script-src-elem")

    # script-src-elem: nonces required for inline <script> blocks; no strict-dynamic.
    # External: Cloudflare Web Analytics, same-origin + CDNs.
    assert String.contains?(csp, "script-src-elem 'self' 'nonce-abc123'")
    assert String.contains?(csp, "https://static.cloudflareinsights.com")
    assert String.contains?(csp, "connect-src")
    assert String.contains?(csp, "img-src")
  end

  test "adds HSTS header only in production and only for https" do
    # production (anything other than :dev) + https
    Application.put_env(:ysc, :environment, :prod)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: false)

    https_conn =
      conn(:get, "/")
      |> Map.put(:scheme, :https)
      |> SecurityHeaders.call([])

    assert get_resp_header(https_conn, "strict-transport-security") != []

    http_conn =
      conn(:get, "/")
      |> Map.put(:scheme, :http)
      |> SecurityHeaders.call([])

    assert get_resp_header(http_conn, "strict-transport-security") == []
  end

  test "in production, CSP includes upgrade-insecure-requests" do
    Application.put_env(:ysc, :environment, :prod)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: false)

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "n")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    assert String.contains?(csp, "upgrade-insecure-requests")
  end

  test "in dev, CSP does not include upgrade-insecure-requests" do
    Application.put_env(:ysc, :environment, :dev)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: true)

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "n")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    refute String.contains?(csp, "upgrade-insecure-requests")
  end

  test "skips CSP on LiveDashboard paths but still sets other security headers" do
    Application.put_env(:ysc, :environment, :dev)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: true)

    conn = SecurityHeaders.call(conn(:get, "/admin/dashboard/live"), [])

    assert get_resp_header(conn, "content-security-policy") == []
    assert get_resp_header(conn, "referrer-policy") != []
    assert get_resp_header(conn, "x-frame-options") != []
  end

  test "uses empty nonce when csp_nonce assign is missing" do
    Application.put_env(:ysc, :environment, :dev)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: true)

    conn = SecurityHeaders.call(conn(:get, "/"), [])

    [csp] = get_resp_header(conn, "content-security-policy")
    assert String.contains?(csp, "'nonce-'")
  end

  test "in production, sets HSTS when x-forwarded-proto is https even if scheme is http" do
    Application.put_env(:ysc, :environment, :prod)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: false)

    conn =
      conn(:get, "/")
      |> Map.put(:scheme, :http)
      |> put_req_header("x-forwarded-proto", "https")
      |> SecurityHeaders.call([])

    assert get_resp_header(conn, "strict-transport-security") != []
  end

  test "includes connect-src and frame rules for production without dev localhost" do
    Application.put_env(:ysc, :environment, :prod)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: false)

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "n")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    refute String.contains?(csp, "http://localhost:*")
    assert String.contains?(csp, "connect-src")
    assert String.contains?(csp, "frame-ancestors 'self'")
  end

  test "adds custom S3 base URL hosts to img-src and connect-src" do
    Application.put_env(:ysc, :environment, :prod)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: false)
    Application.put_env(:ysc, :s3_base_url, "https://cdn.example.com")

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "x")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    assert String.contains?(csp, "https://cdn.example.com")
  end

  test "adds S3 public storage URLs to connect-src for custom Tigris domains" do
    Application.put_env(:ysc, :environment, :prod)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: false)
    old_media = Application.get_env(:ysc, :s3_media_public_url)

    on_exit(fn ->
      if old_media == nil do
        Application.delete_env(:ysc, :s3_media_public_url)
      else
        Application.put_env(:ysc, :s3_media_public_url, old_media)
      end
    end)

    Application.put_env(
      :ysc,
      :s3_media_public_url,
      "https://assets.example.com"
    )

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "x")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    assert String.contains?(csp, "connect-src")
    assert String.contains?(csp, "https://assets.example.com")
  end

  test "omits MinIO connect host when code_reloader is false" do
    Application.put_env(:ysc, :environment, :dev)
    Application.put_env(:ysc, YscWeb.Endpoint, code_reloader: false)
    Application.put_env(:ysc, :s3_base_url, "https://cdn.example.com")

    conn =
      conn(:get, "/")
      |> assign(:csp_nonce, "n")
      |> SecurityHeaders.call([])

    [csp] = get_resp_header(conn, "content-security-policy")
    refute String.contains?(csp, "http://localhost:9000")
  end
end
