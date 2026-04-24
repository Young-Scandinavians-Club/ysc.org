defmodule Ysc.MobileAPIRateLimit do
  @moduledoc """
  Per-IP rate limiting for the `/api/v1/mobile` (kiosk) JSON API.

  Mitigates scraping and abuse of the shared `KIOSK_API_KEY` surface. Tuned
  higher than auth flows since kiosks poll legitimately; adjust via
  `config :ysc, Ysc.MobileAPIRateLimit, ip_limit: n`.
  """
  use Hammer, backend: :ets

  @default_ip_limit 120
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
    key = "mobile_api:ip:#{String.trim(ip)}"

    case hit(key, @ip_scale_ms, ip_limit()) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        {:error, :rate_limited, max(1, div(retry_after_ms, 1000))}
    end
  end
end
