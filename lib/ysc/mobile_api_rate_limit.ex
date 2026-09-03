defmodule Ysc.MobileAPIRateLimit do
  @moduledoc """
  Per-IP rate limiting for the `/api/v1/mobile` (kiosk) JSON API.

  Mitigates scraping and abuse of the shared `KIOSK_API_KEY` surface. Tuned
  higher than auth flows since kiosks poll legitimately; adjust via
  `config :ysc, Ysc.MobileAPIRateLimit, ip_limit: n`.
  """
  use Hammer, backend: :ets

  alias Ysc.RateLimit

  @default_ip_limit 120
  @ip_scale_ms :timer.minutes(1)

  defp ip_limit do
    Application.get_env(:ysc, __MODULE__, [])[:ip_limit] || @default_ip_limit
  end

  @doc """
  Returns `:ok` or `{:error, :rate_limited, retry_after_seconds}`.
  """
  def check_ip(ip) when is_tuple(ip) or is_binary(ip) do
    RateLimit.check_ip(&hit/3, "mobile_api:ip:", ip, @ip_scale_ms, ip_limit())
  end
end
