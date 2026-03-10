defmodule Ysc.Alerts.DiscordHttpBehaviour do
  @moduledoc """
  Behaviour for Discord webhook HTTP transport.
  Allows mocking in tests without making real network calls.
  """

  @callback send_webhook(
              url :: String.t(),
              body :: String.t(),
              headers :: list()
            ) ::
              {:ok, :sent} | {:error, any()}
end
