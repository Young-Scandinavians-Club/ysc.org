defmodule Ysc.Keila.Behaviour do
  @moduledoc """
  Behaviour for Keila API interactions.
  """

  @callback subscribe_email(String.t(), keyword()) :: :ok | {:error, any()}
  @callback unsubscribe_email(String.t(), keyword()) :: :ok | {:error, any()}
  @callback get_subscription_status(String.t(), keyword()) ::
              {:ok, atom()} | {:error, any()}
end
