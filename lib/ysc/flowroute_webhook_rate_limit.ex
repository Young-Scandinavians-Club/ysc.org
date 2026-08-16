defmodule Ysc.FlowrouteWebhookRateLimit do
  @moduledoc """
  Per-IP rate limiting for the `/webhooks/flowroute/*` routes.

  These routes are gated only by a static token baked into the URL (FlowRoute
  has no HMAC webhook signing), so nothing else stops an attacker who has
  leaked or is guessing that token from hammering the endpoint. Tuned well
  above legitimate FlowRoute traffic (including retries) but low enough to
  blunt brute-forcing; adjust via `config :ysc, Ysc.FlowrouteWebhookRateLimit,
  ip_limit: n`.
  """
  use Hammer, backend: :ets

  @default_ip_limit 60
  @ip_scale_ms :timer.minutes(1)

  defp ip_limit do
    Application.get_env(:ysc, __MODULE__, [])[:ip_limit] || @default_ip_limit
  end

  @doc """
  Returns `:ok` or `{:error, :rate_limited, retry_after_seconds}`.
  """
  def check_ip(ip) when is_tuple(ip) do
    ip
    |> :inet.ntoa()
    |> to_string()
    |> check_ip()
  end

  def check_ip(ip) when is_binary(ip) do
    key = "flowroute_webhook:ip:#{String.trim(ip)}"

    case hit(key, @ip_scale_ms, ip_limit()) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        {:error, :rate_limited, max(1, div(retry_after_ms, 1000))}
    end
  end
end
