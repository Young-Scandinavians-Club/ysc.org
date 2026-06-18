defmodule Ysc.Stripe.RetryHelperTest do
  use ExUnit.Case, async: true

  alias Ysc.Stripe.RetryHelper

  describe "transient_stripe_error?/1" do
    test "detects connection and rate-limit errors" do
      assert RetryHelper.transient_stripe_error?(
               stripe_error(:api_connection_error)
             )

      assert RetryHelper.transient_stripe_error?(
               stripe_error(:rate_limit_error)
             )

      assert RetryHelper.transient_stripe_error?(
               stripe_error(:too_many_requests)
             )
    end

    test "detects retryable 5xx responses" do
      assert RetryHelper.transient_stripe_error?(%Stripe.Error{
               source: :stripe,
               code: :api_error,
               message: "server error",
               extra: %{http_status: 503}
             })
    end

    test "does not treat resource_missing as transient" do
      refute RetryHelper.transient_stripe_error?(
               stripe_error(:resource_missing)
             )
    end
  end

  defp stripe_error(code) do
    %Stripe.Error{source: :stripe, code: code, message: "test", extra: %{}}
  end
end
