defmodule YscWeb.PaymentMethodFormatterTest do
  use ExUnit.Case, async: true

  alias YscWeb.PaymentMethodFormatter

  describe "normalize_payment_type/1" do
    test "normalizes shared payment method aliases consistently" do
      assert PaymentMethodFormatter.normalize_payment_type("bank_account") ==
               :bank_account

      assert PaymentMethodFormatter.normalize_payment_type("apple_pay") ==
               :apple_pay

      assert PaymentMethodFormatter.normalize_payment_type("google_pay") ==
               :google_pay
    end
  end

  describe "payment_brand_label/1" do
    test "keeps multi-word wallet brands correctly cased" do
      assert PaymentMethodFormatter.payment_brand_label("Apple Pay") ==
               "Apple Pay"

      assert PaymentMethodFormatter.payment_brand_label("Google Pay") ==
               "Google Pay"
    end

    test "title-cases underscore-separated fallback brands" do
      assert PaymentMethodFormatter.payment_brand_label("diners_club") ==
               "Diners Club"
    end
  end

  describe "extract_payment_method_details/1" do
    test "extracts string-keyed Link wallet payment methods defensively" do
      stripe_pm = %{
        "type" => "card",
        "card" => %{
          "brand" => "visa",
          "last4" => "1111",
          "wallet" => %{"type" => "link", "dynamic_last4" => "4242"}
        }
      }

      assert PaymentMethodFormatter.extract_payment_method_details(stripe_pm) ==
               {"link", "4242", "visa"}
    end

    test "extracts atom-keyed Apple Pay wallet display brand defensively" do
      stripe_pm = %{
        type: "card",
        card: %{
          brand: "visa",
          last4: "1111",
          wallet: %{type: "apple_pay"}
        }
      }

      assert PaymentMethodFormatter.extract_payment_method_details(stripe_pm) ==
               {"card", "1111", "Apple Pay"}
    end
  end

  describe "format_payment_method_with_details/3" do
    test "formats normalized bank account aliases" do
      assert PaymentMethodFormatter.format_payment_method_with_details(
               "bank_account",
               "6789",
               "Test Bank"
             ) == "Test Bank Account ending in 6789"
    end
  end
end
