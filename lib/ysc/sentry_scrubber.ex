defmodule Ysc.SentryScrubber do
  @moduledoc false

  # Sentry 13.3+ scrubs password/passwd/secret from URLs by default. Extend the
  # list for auth flows that put one-time tokens in query strings.
  @sensitive_param_keys Sentry.Scrubber.default_param_keys() ++
                          ~w(token setup_token code)

  # FlowRoute and Printful have no HMAC webhook signing, so the shared secret
  # is baked into the URL path (/webhooks/flowroute/<token>/...,
  # /webhooks/printful/<token>) rather than a query param or header —
  # Sentry.Scrubber.scrub_url/2 only scrubs query strings, so it wouldn't
  # otherwise catch this. Finding 91: Printful was missed when merch landed.
  @webhook_token_path ~r{(/webhooks/(?:flowroute|printful)/)[^/?#]+}

  @spec scrub_url(Plug.Conn.t()) :: String.t()
  def scrub_url(conn) do
    conn
    |> Plug.Conn.request_url()
    |> String.replace(@webhook_token_path, "\\1[REDACTED]")
    |> Sentry.Scrubber.scrub_url(keys: @sensitive_param_keys)
  end

  @spec scrub_params(Plug.Conn.t()) :: map()
  def scrub_params(conn) do
    conn
    |> Sentry.PlugContext.default_body_scrubber()
    |> Sentry.Scrubber.scrub(keys: @sensitive_param_keys)
  end
end
