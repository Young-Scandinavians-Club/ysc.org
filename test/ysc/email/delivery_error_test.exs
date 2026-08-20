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

  test "Swoosh AmazonSES XML helpers return empty strings for missing error nodes" do
    alias Swoosh.Adapters.XML.Helpers, as: XMLHelper

    node = XMLHelper.parse("<ErrorResponse><Error></Error></ErrorResponse>")

    assert XMLHelper.first_text(node, "//Error/Code") == ""
    assert XMLHelper.first_text(node, "//Message") == ""
  end

  test "treats blank SES error codes as unknown and retryable" do
    # Swoosh 1.27.1 AmazonSES parse_error_response/1 returns empty strings when
    # Error/Code or Message nodes are missing from the XML body.
    error =
      DeliveryError.classify({:error, %{code: "", message: ""}})

    assert error.category == :unknown
    assert error.code == ""
    assert DeliveryError.retryable?(error)

    whitespace =
      DeliveryError.classify({:error, %{code: "   ", message: "malformed xml"}})

    assert whitespace.category == :unknown
    assert DeliveryError.retryable?(whitespace)
  end

  test "treats ambiguous transport failures as retryable" do
    assert %{category: :transient} = DeliveryError.classify({:error, :timeout})

    assert %{category: :unknown} =
             DeliveryError.classify({:error, {:closed, :unexpected}})
  end
end
