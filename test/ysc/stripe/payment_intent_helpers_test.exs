defmodule Ysc.Stripe.PaymentIntentHelpersTest do
  use ExUnit.Case, async: true

  alias Ysc.Stripe.PaymentIntentHelpers

  describe "first_expanded_charge/1" do
    test "returns expanded Stripe.Charge from latest_charge on struct" do
      charge = %Stripe.Charge{id: "ch_struct"}

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_struct",
        latest_charge: charge
      }

      assert PaymentIntentHelpers.first_expanded_charge(payment_intent) ==
               charge
    end

    test "returns expanded charge map from latest_charge" do
      charge = %{"id" => "ch_map", "amount" => 5000}

      assert PaymentIntentHelpers.first_expanded_charge(%{
               latest_charge: charge
             }) == charge

      assert PaymentIntentHelpers.first_expanded_charge(%{
               "latest_charge" => charge
             }) == charge
    end

    test "returns nil when latest_charge is only a charge id string" do
      payment_intent = %Stripe.PaymentIntent{
        id: "pi_string_charge",
        latest_charge: "ch_unexpanded"
      }

      assert PaymentIntentHelpers.first_expanded_charge(payment_intent) == nil
    end

    test "falls back to legacy charges.data when latest_charge is absent" do
      charge = %Stripe.Charge{id: "ch_legacy"}

      payment_intent = %{
        latest_charge: nil,
        charges: %Stripe.List{data: [charge]}
      }

      assert PaymentIntentHelpers.first_expanded_charge(payment_intent) ==
               charge
    end

    test "reads legacy charges from plain maps" do
      charge = %{"id" => "ch_legacy_map"}

      assert PaymentIntentHelpers.first_expanded_charge(%{
               charges: %{"data" => [charge]}
             }) == charge
    end

    test "returns nil for unsupported input" do
      assert PaymentIntentHelpers.first_expanded_charge(nil) == nil
      assert PaymentIntentHelpers.first_expanded_charge("not-a-map") == nil
      assert PaymentIntentHelpers.first_expanded_charge(%{}) == nil
    end
  end

  describe "charge_id/1" do
    test "returns latest_charge when it is a charge id string" do
      payment_intent = %Stripe.PaymentIntent{
        id: "pi_string",
        latest_charge: "ch_latest"
      }

      assert PaymentIntentHelpers.charge_id(payment_intent) == "ch_latest"
    end

    test "extracts id from expanded charge struct or map" do
      assert PaymentIntentHelpers.charge_id(%Stripe.PaymentIntent{
               latest_charge: %Stripe.Charge{id: "ch_from_struct"}
             }) == "ch_from_struct"

      assert PaymentIntentHelpers.charge_id(%{latest_charge: %{id: "ch_atom"}}) ==
               "ch_atom"

      assert PaymentIntentHelpers.charge_id(%{
               "latest_charge" => %{"id" => "ch_string"}
             }) ==
               "ch_string"
    end

    test "falls back to legacy charges.data when latest_charge is absent" do
      payment_intent = %{
        latest_charge: nil,
        charges: %Stripe.List{data: [%Stripe.Charge{id: "ch_legacy_id"}]}
      }

      assert PaymentIntentHelpers.charge_id(payment_intent) == "ch_legacy_id"
    end

    test "reads legacy charge ids from plain maps" do
      assert PaymentIntentHelpers.charge_id(%{
               charges: %{data: [%{id: "ch_map_legacy"}]}
             }) == "ch_map_legacy"
    end

    test "returns nil when no charge is available" do
      assert PaymentIntentHelpers.charge_id(%Stripe.PaymentIntent{
               id: "pi_empty"
             }) ==
               nil

      assert PaymentIntentHelpers.charge_id(nil) == nil
      assert PaymentIntentHelpers.charge_id(%{}) == nil
    end
  end
end
