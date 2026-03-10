defmodule Ysc.Alerts.DiscordHttpClient do
  @moduledoc """
  Real HTTP client for Discord webhook delivery using Finch.
  """

  @behaviour Ysc.Alerts.DiscordHttpBehaviour

  @impl true
  def send_webhook(url, body, headers) do
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Ysc.Finch) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:ok, :sent}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        {:error, {:bad_status, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, error}
  end
end
