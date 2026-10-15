defmodule Ysc.Merch.Webhooks do
  @moduledoc """
  Registers our webhook URL with Printful so it tells us when orders ship.

  The callback URL contains `PRINTFUL_WEBHOOK_SECRET` (see
  `YscWeb.PrintfulWebhookController`). Printful must be able to reach it, so
  it only works from a publicly reachable HTTPS host.
  """
  alias Ysc.Merch.PrintfulEvents

  defp printful_client do
    Application.get_env(:ysc, :printful_client, Ysc.Printful.Client)
  end

  @doc """
  The full callback URL, or `{:error, :no_secret}` when no secret is set.
  """
  @spec callback_url() :: {:ok, String.t()} | {:error, :no_secret}
  def callback_url do
    case Application.get_env(:ysc, :printful, [])[:webhook_secret] do
      secret when is_binary(secret) and secret != "" ->
        {:ok, "#{YscWeb.Endpoint.url()}/webhooks/printful/#{secret}"}

      _ ->
        {:error, :no_secret}
    end
  end

  @doc """
  Tells Printful to send our event types to the callback URL. Returns the
  URL with the secret masked, safe to show in the admin.
  """
  @spec register() ::
          {:ok, String.t()} | {:error, :no_secret | Ysc.Printful.Error.t()}
  def register do
    with {:ok, url} <- callback_url(),
         {:ok, _result} <-
           printful_client().set_webhooks(
             url,
             PrintfulEvents.subscribed_types()
           ) do
      {:ok, mask(url)}
    end
  end

  @doc "The callback URL with its secret replaced, for display."
  def mask(url) when is_binary(url) do
    String.replace(url, ~r{(/webhooks/printful/).+$}, "\\1••••••••")
  end
end
