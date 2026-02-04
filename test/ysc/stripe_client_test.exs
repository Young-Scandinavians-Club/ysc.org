defmodule Ysc.StripeClientTest do
  use ExUnit.Case, async: true

  alias Ysc.StripeClient

  describe "StripeBehaviour implementation" do
    test "implements all expected functions with correct arities" do
      # This test verifies the functions exist and have the correct arity
      # Actual Stripe API calls should be tested with mocks in integration tests
      functions = StripeClient.__info__(:functions)

      assert {:create_payment_intent, 2} in functions
      assert {:retrieve_payment_intent, 2} in functions
      assert {:cancel_payment_intent, 2} in functions
      assert {:create_customer, 1} in functions
      assert {:update_customer, 2} in functions
      assert {:retrieve_payment_method, 1} in functions
    end
  end

  describe "behaviour compliance" do
    test "implements all Ysc.StripeBehaviour callbacks" do
      behaviour_callbacks = Ysc.StripeBehaviour.behaviour_info(:callbacks)
      implemented_functions = StripeClient.__info__(:functions)

      Enum.each(behaviour_callbacks, fn {function, arity} ->
        assert {function, arity} in implemented_functions,
               "#{function}/#{arity} not implemented"
      end)
    end
  end
end
