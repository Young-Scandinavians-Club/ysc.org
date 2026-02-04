defmodule Ysc.Keila do
  @moduledoc """
  The Keila context for managing newsletter subscriptions.
  Delegates to the configured Keila client.
  """

  def subscribe_email(email, opts \\ []) do
    if valid_email?(email) do
      client().subscribe_email(email, opts)
    else
      {:error, :invalid_email}
    end
  end

  def unsubscribe_email(email, opts \\ []) do
    if valid_email?(email) do
      client().unsubscribe_email(email, opts)
    else
      {:error, :invalid_email}
    end
  end

  def get_subscription_status(email, opts \\ []) do
    if valid_email?(email) do
      client().get_subscription_status(email, opts)
    else
      {:error, :invalid_email}
    end
  end

  defp client do
    Application.get_env(:ysc, :keila_client, Ysc.Keila.Client)
  end

  defp valid_email?(email) do
    is_binary(email) && email != "" && String.contains?(email, "@")
  end
end
