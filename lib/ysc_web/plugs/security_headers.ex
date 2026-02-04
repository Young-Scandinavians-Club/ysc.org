defmodule YscWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Sets security headers including CSP with nonce support.
  This plug should be called after CSPNonce plug to ensure the nonce is available.
  """
  import Plug.Conn
  alias Ysc.S3Config

  def init(opts), do: opts

  def call(conn, _opts) do
    # Skip CSP for LiveDashboard routes - it has its own CSP handling
    if live_dashboard_route?(conn) do
      conn
      |> put_non_csp_security_headers()
    else
      nonce = conn.assigns[:csp_nonce] || ""

      # Check if we're in development mode
      is_dev = Ysc.Env.dev?()

      # Get S3 storage URLs for image sources
      s3_image_sources = get_s3_image_sources()

      # Get S3 storage URLs for connect sources (for uploads)
      s3_connect_sources = get_s3_connect_sources()

      # Build CSP policy with nonce
      csp_policy =
        build_csp_policy(nonce, is_dev, s3_image_sources, s3_connect_sources)

      conn
      |> put_resp_header("content-security-policy", csp_policy)
      |> put_non_csp_security_headers()
    end
  end

  defp live_dashboard_route?(conn) do
    # Check if the request path starts with /admin/dashboard
    case conn.request_path do
      "/admin/dashboard" <> _ -> true
      _ -> false
    end
  end

  defp put_non_csp_security_headers(conn) do
    is_dev = Ysc.Env.dev?()

    conn
    |> put_resp_header(
      "permissions-policy",
      # Allow payment for Stripe, block other features
      "camera=(), microphone=(), geolocation=(), payment=(self \"https://js.stripe.com\"), usb=(), magnetometer=(), gyroscope=()"
    )
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("cross-origin-opener-policy", "same-origin")
    |> put_resp_header("cross-origin-resource-policy", "same-origin")
    |> put_resp_header("cross-origin-embedder-policy", "unsafe-none")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_hsts_header(is_dev)
  end

  defp build_csp_policy(nonce, is_dev, s3_image_sources, s3_connect_sources) do
    # Base sources
    default_src = "'self'"

    # Script sources - use strict-dynamic with nonce for maximum security
    # 'strict-dynamic' allows scripts loaded by nonce-approved scripts to execute
    # The allowlist entries are ignored by browsers supporting strict-dynamic but
    # kept for backward compatibility with older browsers
    # 'unsafe-inline' is ignored when nonce is present but kept for older browsers
    # Allowlist for older browsers (ignored when strict-dynamic is present)
    # Allow inline scripts for older browsers that don't support strict-dynamic or nonce
    script_src =
      ([
         "'self'",
         "'nonce-#{nonce}'",
         "'strict-dynamic'",
         "'unsafe-inline'",
         "https://js.stripe.com/v3/",
         "https://js.radar.com/v4.4.8/radar.min.js",
         "https://unpkg.com/glightbox/dist/js/glightbox.min.js",
         "https://challenges.cloudflare.com"
       ] ++
         if(is_dev,
           do: [],
           else: []
         ))
      |> Enum.join(" ")

    # Style sources - allow self, unsafe-inline, and external CDNs
    # Note: Nonces don't work for style attributes (style="..."), only for <style> tags.
    # When nonce is present, 'unsafe-inline' is ignored, so we remove nonce from style-src.
    # We use 'unsafe-inline' which covers both <style> tags and style attributes.
    style_src =
      [
        "'self'",
        # Required for inline style attributes and <style> tags
        "'unsafe-inline'",
        "https://js.radar.com/v4.4.8/radar.css",
        "https://unpkg.com/glightbox/dist/css/glightbox.min.css"
      ]
      |> Enum.join(" ")

    # Connect sources - allow WebSockets for LiveView
    # In dev, allow both ws: and wss:, in prod only wss:
    # Also allow Stripe, Cloudflare Turnstile, Radar API, and S3 storage for uploads
    base_connect_sources =
      if is_dev do
        [
          "'self'",
          "ws:",
          "wss:",
          "http://localhost:*",
          "https://localhost:*",
          "https://js.stripe.com",
          "https://challenges.cloudflare.com",
          "https://api.radar.io"
        ]
      else
        [
          "'self'",
          "wss:",
          "https://js.stripe.com",
          "https://challenges.cloudflare.com",
          "https://api.radar.io"
        ]
      end

    connect_src = (base_connect_sources ++ s3_connect_sources) |> Enum.join(" ")

    # Image sources - include S3 storage domains
    # Allow all HTTPS images (covers production S3)
    img_src =
      ([
         "'self'",
         "data:",
         "blob:",
         "https:"
       ] ++ s3_image_sources)
      |> Enum.join(" ")

    # Font sources - allow Radar fonts
    font_src =
      [
        "'self'",
        "data:",
        # Radar library loads fonts from radar.com
        "https://radar.com"
      ]
      |> Enum.join(" ")

    # Frame sources - allow Stripe, Cloudflare Turnstile, and localhost for dev tools
    frame_src =
      if is_dev do
        "'self' http://localhost:* https://localhost:* https://js.stripe.com https://challenges.cloudflare.com"
      else
        "https://js.stripe.com https://challenges.cloudflare.com"
      end

    # Worker sources - allow blob: workers (Radar library creates workers from blob URLs)
    worker_src = "'self' blob:"

    # Object sources - deny by default
    object_src = "'none'"

    # Base URI
    base_uri = "'self'"

    # Form action - allow self and Stripe
    form_action = "'self' https://js.stripe.com"

    # Frame ancestors - allow localhost in dev for dev inbox, deny otherwise
    frame_ancestors = if is_dev, do: "'self' http://localhost:*", else: "'none'"

    # Upgrade insecure requests - only in production
    # In development, we need to allow HTTP for LocalStack
    base_policy = [
      "default-src #{default_src}",
      "script-src #{script_src}",
      "style-src #{style_src}",
      "connect-src #{connect_src}",
      "img-src #{img_src}",
      "font-src #{font_src}",
      "frame-src #{frame_src}",
      "worker-src #{worker_src}",
      "object-src #{object_src}",
      "base-uri #{base_uri}",
      "form-action #{form_action}",
      "frame-ancestors #{frame_ancestors}"
    ]

    # Only add upgrade-insecure-requests in production
    policy =
      if is_dev do
        base_policy
      else
        base_policy ++ ["upgrade-insecure-requests"]
      end

    policy |> Enum.join("; ")
  end

  # Get S3 storage URLs that should be allowed for connect operations (uploads)
  defp get_s3_connect_sources do
    base_url = S3Config.base_url()
    sources = []

    sources =
      if base_url && base_url != "" do
        add_base_url_source(sources, base_url)
      else
        sources
      end

    sources =
      ["https://*.fly.storage.tigris.dev" | sources]
      |> Enum.uniq()

    sources =
      if Application.get_env(:ysc, YscWeb.Endpoint)[:code_reloader] == true do
        ["http://*.localhost.localstack.cloud:4566" | sources]
      else
        sources
      end

    Enum.uniq(sources)
  end

  defp add_base_url_source(sources, base_url) do
    case URI.parse(base_url) do
      %URI{scheme: scheme, host: host, port: port} when not is_nil(host) ->
        source = build_source_from_uri(scheme, host, port)

        if source, do: [source | sources], else: sources

      _ ->
        sources
    end
  end

  defp build_source_from_uri("http", host, 4566) do
    "http://#{host}:#{4566}"
  end

  defp build_source_from_uri("https", host, nil) do
    if String.contains?(host, "tigris.dev") do
      "https://*.fly.storage.tigris.dev"
    else
      "https://#{host}"
    end
  end

  defp build_source_from_uri(scheme, host, nil)
       when scheme in ["http", "https"] do
    "#{scheme}://#{host}"
  end

  defp build_source_from_uri(scheme, host, port)
       when scheme in ["http", "https"] and not is_nil(port) do
    "#{scheme}://#{host}:#{port}"
  end

  defp build_source_from_uri(_, _, _), do: nil

  # Get S3 storage URLs that should be allowed for images
  defp get_s3_image_sources do
    base_url = S3Config.base_url()
    sources = []

    sources =
      if base_url && base_url != "" do
        add_base_url_source(sources, base_url)
      else
        sources
      end

    sources =
      ["https://*.fly.storage.tigris.dev" | sources]
      |> Enum.uniq()

    sources =
      if Application.get_env(:ysc, YscWeb.Endpoint)[:code_reloader] == true do
        ["http://*.localhost.localstack.cloud:4566" | sources]
      else
        sources
      end

    Enum.uniq(sources)
  end

  # Set HSTS header only on HTTPS connections and only in production
  defp put_hsts_header(conn, is_dev) do
    # Only set HSTS in production (not in development)
    # HSTS should only be set on HTTPS connections
    if is_dev do
      conn
    else
      # Check if the connection is HTTPS (either directly or via proxy)
      is_https =
        case get_req_header(conn, "x-forwarded-proto") do
          ["https"] -> true
          _ -> conn.scheme == :https
        end

      if is_https do
        # Set HSTS with 1 year max-age and includeSubDomains
        # max-age: 31,536,000 seconds = 1 year
        # includeSubDomains: Apply to all subdomains
        put_resp_header(
          conn,
          "strict-transport-security",
          "max-age=31536000; includeSubDomains"
        )
      else
        conn
      end
    end
  end
end
