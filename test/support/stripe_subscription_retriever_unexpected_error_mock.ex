defmodule Ysc.StripeSubscriptionRetrieverUnexpectedErrorMock do
  @moduledoc false

  def retrieve(_stripe_id), do: {:error, :unexpected}
end
