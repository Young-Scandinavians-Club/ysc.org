defmodule Ysc.PrintfulWebhookRateLimit do
  @moduledoc """
  Per-IP rate limiting for `/webhooks/printful/:token`.

  The route is gated by a secret token in the URL, so this is what stops
  someone who has leaked or is guessing the token from hammering it. Well
  above Printful's real traffic (including retries); tune with
  `config :ysc, Ysc.PrintfulWebhookRateLimit, ip_limit: n`.
  """
  use Hammer, backend: :ets

  alias Ysc.RateLimit

  @default_ip_limit 60
  @ip_scale_ms :timer.minutes(1)

  defp ip_limit do
    Application.get_env(:ysc, __MODULE__, [])[:ip_limit] || @default_ip_limit
  end

  @doc "Returns `:ok` or `{:error, :rate_limited, retry_after_seconds}`."
  def check_ip(ip) when is_tuple(ip) or is_binary(ip) do
    RateLimit.check_ip(
      &hit/3,
      "printful_webhook:ip:",
      ip,
      @ip_scale_ms,
      ip_limit()
    )
  end
end
