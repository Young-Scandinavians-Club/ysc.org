defmodule Ysc.Keila.ClientStub do
  @moduledoc """
  Stub implementation of Keila.Behaviour for tests.
  """
  @behaviour Ysc.Keila.Behaviour

  def subscribe_email(_email, _opts), do: :ok
  def unsubscribe_email(_email, _opts), do: :ok
  def get_subscription_status(_email, _opts), do: {:ok, :active}
end
