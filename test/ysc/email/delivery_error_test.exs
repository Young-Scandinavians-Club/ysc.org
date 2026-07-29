defmodule Ysc.Email.DeliveryErrorTest do
  use ExUnit.Case, async: true

  alias Ysc.Email.DeliveryError

  test "classifies SES throttling as retryable rate limiting" do
    error =
      DeliveryError.classify(
        {:error,
         %{code: "Throttling", message: "Maximum sending rate exceeded"}}
      )

    assert error.category == :rate_limited
    assert error.code == "Throttling"
    assert DeliveryError.retryable?(error)
  end

  test "classifies SES message rejection as permanent" do
    error =
      DeliveryError.classify(
        {:error,
         %{code: "MessageRejected", message: "Email address is not verified"}}
      )

    assert error.category == :permanent
    refute DeliveryError.retryable?(error)
  end

  test "treats ambiguous transport failures as retryable" do
    assert %{category: :transient} = DeliveryError.classify({:error, :timeout})

    assert %{category: :unknown} =
             DeliveryError.classify({:error, {:closed, :unexpected}})
  end
end
