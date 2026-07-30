defmodule YscWeb.PaymentMethodLogoTest do
  use ExUnit.Case, async: true

  alias Ysc.Payments.PaymentMethod
  alias YscWeb.PaymentMethodLogo

  describe "path_for_payment/1" do
    test "returns nil when payment_method is nil" do
      assert PaymentMethodLogo.path_for_payment(nil) == nil
      assert PaymentMethodLogo.path_for_payment(%{payment_method: nil}) == nil
    end

    test "delegates to path_for_payment_method when payment_method is present" do
      payment = %{
        payment_method: %PaymentMethod{
          type: :card,
          display_brand: "visa",
          last_four: "4242"
        }
      }

      assert PaymentMethodLogo.path_for_payment(payment) ==
               "/images/cards/visa.png"
    end

    test "returns nil for unrelated structs" do
      assert PaymentMethodLogo.path_for_payment(%{foo: :bar}) == nil
    end
  end

  describe "path_for_payment_method/1" do
    test "returns Link logo for stored link payment methods" do
      pm = %PaymentMethod{type: :link, display_brand: "visa", last_four: "4242"}

      assert PaymentMethodLogo.path_for_payment_method(pm) ==
               "/images/cards/link.png"
    end

    test "returns card brand file for card payment methods" do
      pm = %PaymentMethod{type: :card, display_brand: "visa", last_four: "4242"}

      assert PaymentMethodLogo.path_for_payment_method(pm) ==
               "/images/cards/visa.png"
    end

    test "accepts plain maps with a type field" do
      pm = %{type: :card, display_brand: "Mastercard", last_four: "1234"}

      assert PaymentMethodLogo.path_for_payment_method(pm) ==
               "/images/cards/mc.svg"
    end

    test "returns nil for maps without a type field" do
      assert PaymentMethodLogo.path_for_payment_method(%{display_brand: "visa"}) ==
               nil
    end

    test "normalizes card brand aliases" do
      assert PaymentMethodLogo.path_for_payment_method(%{
               type: :card,
               display_brand: "American Express"
             }) == "/images/cards/amex.svg"

      assert PaymentMethodLogo.path_for_payment_method(%{
               type: :card,
               display_brand: "Diners Club"
             }) == "/images/cards/diners.svg"

      assert PaymentMethodLogo.path_for_payment_method(%{
               type: :card,
               display_brand: "JCB"
             }) == "/images/cards/jcb.svg"
    end

    test "returns alternative payment logos for non-card types" do
      assert PaymentMethodLogo.path_for_payment_method(%{type: :cashapp}) ==
               "/images/cards/cashapp.svg"

      assert PaymentMethodLogo.path_for_payment_method(%{type: :paypal}) ==
               "/images/cards/paypal.svg"

      assert PaymentMethodLogo.path_for_payment_method(%{type: :apple_pay}) ==
               "/images/cards/apple.svg"
    end

    test "returns nil for bank account types" do
      assert PaymentMethodLogo.path_for_payment_method(%{type: :bank_account}) ==
               nil
    end
  end

  describe "path_for_stripe_summary/2" do
    test "returns Link logo for stripe summary type link" do
      assert PaymentMethodLogo.path_for_stripe_summary(:link, nil) ==
               "/images/cards/link.png"
    end

    test "returns card brand file for stripe summary cards" do
      assert PaymentMethodLogo.path_for_stripe_summary(:card, "discover") ==
               "/images/cards/discover.svg"
    end

    test "returns alternative payment logos" do
      assert PaymentMethodLogo.path_for_stripe_summary(:klarna, nil) ==
               "/images/cards/klarna.svg"

      assert PaymentMethodLogo.path_for_stripe_summary(:google_pay, nil) ==
               "/images/cards/google.svg"
    end

    test "returns nil for bank account stripe summary types" do
      assert PaymentMethodLogo.path_for_stripe_summary(:bank_account, nil) == nil
      assert PaymentMethodLogo.path_for_stripe_summary(:us_bank_account, nil) == nil
      assert PaymentMethodLogo.path_for_stripe_summary(:sepa_debit, nil) == nil
    end

    test "returns nil for unknown stripe summary types" do
      assert PaymentMethodLogo.path_for_stripe_summary(:other, nil) == nil
    end
  end
end
