defmodule Ysc.SentryScrubber do
  @moduledoc false

  # Sentry 13.3+ scrubs password/passwd/secret from URLs by default. Extend the
  # list for auth flows that put one-time tokens in query strings.
  @sensitive_param_keys Sentry.Scrubber.default_param_keys() ++
                          ~w(token setup_token code)

  # FlowRoute has no HMAC webhook signing, so its shared secret is baked into
  # the URL path itself (/webhooks/flowroute/<token>/...) rather than a query
  # param or header — Sentry.Scrubber.scrub_url/2 only scrubs query strings,
  # so it wouldn't otherwise catch this.
  @flowroute_token_path ~r{(/webhooks/flowroute/)[^/]+(/)}

  @spec scrub_url(Plug.Conn.t()) :: String.t()
  def scrub_url(conn) do
    conn
    |> Plug.Conn.request_url()
    |> String.replace(@flowroute_token_path, "\\1[REDACTED]\\2")
    |> Sentry.Scrubber.scrub_url(keys: @sensitive_param_keys)
  end

  @spec scrub_params(Plug.Conn.t()) :: map()
  def scrub_params(conn) do
    conn
    |> Sentry.PlugContext.default_body_scrubber()
    |> Sentry.Scrubber.scrub(keys: @sensitive_param_keys)
  end
end
