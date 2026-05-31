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

  describe "extract_payment_method_details_from_charge/1" do
    test "extracts native Link charge payment_method_details using email or country" do
      charge = %{
        payment_method_details: %{type: "link", link: %{country: "US"}}
      }

      assert PaymentMethodFormatter.extract_payment_method_details_from_charge(
               charge
             ) == {"link", nil, "US"}
    end

    test "extracts Link wallet card from charge payment_method_details" do
      charge = %{
        payment_method_details: %{
          card: %{
            brand: "visa",
            last4: "1111",
            wallet: %{type: "link", dynamic_last4: "4242"}
          }
        }
      }

      assert PaymentMethodFormatter.extract_payment_method_details_from_charge(
               charge
             ) == {"link", "4242", "visa"}
    end
  end

  describe "payment_details_from_payment_intent/2" do
    defmodule StripeClientStub do
      def retrieve_payment_method("pm_plain_card") do
        {:ok,
         %{
           type: "card",
           card: %{brand: "visa", last4: "1111"}
         }}
      end

      def retrieve_payment_method(_id), do: {:error, :not_found}

      def retrieve_charge("ch_link_wallet", _opts) do
        {:ok,
         %{
           payment_method_details: %{
             card: %{
               brand: "visa",
               last4: "9999",
               wallet: %{type: "link", dynamic_last4: "4242"}
             }
           }
         }}
      end

      def retrieve_charge(_id, _opts), do: {:error, :not_found}
    end

    test "uses embedded payment method when it includes last four" do
      payment_intent = %{
        payment_method: %{
          type: "card",
          card: %{brand: "visa", last4: "4242"}
        }
      }

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               StripeClientStub
             ) == {"card", "4242", "visa"}
    end

    test "prefers charge last four when payment method omits wallet dynamic_last4" do
      payment_intent = %{
        payment_method: %{
          type: "card",
          card: %{
            brand: "visa",
            wallet: %{type: "link"}
          }
        },
        latest_charge: %{
          payment_method_details: %{
            card: %{
              brand: "visa",
              last4: "1111",
              wallet: %{type: "link", dynamic_last4: "4242"}
            }
          }
        }
      }

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               StripeClientStub
             ) == {"link", "4242", "visa"}
    end

    test "retrieves payment method by id when intent only stores the id string" do
      payment_intent = %{payment_method: "pm_plain_card"}

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               StripeClientStub
             ) == {"card", "1111", "visa"}
    end

    test "retrieves charge by id when latest_charge is not expanded" do
      payment_intent = %{payment_method: nil, latest_charge: "ch_link_wallet"}

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               StripeClientStub
             ) == {"link", "4242", "visa"}
    end

    test "prefers native Link charge details when payment method is empty" do
      payment_intent = %{
        payment_method: nil,
        latest_charge: %{
          payment_method_details: %{
            type: "link",
            link: %{email: "member@ysc.org"}
          }
        }
      }

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               StripeClientStub
             ) == {"link", nil, "member@ysc.org"}
    end
  end

  describe "format_payment_method_for_receipt/3" do
    test "formats card with PAN mask only (brand shown via logo)" do
      assert PaymentMethodFormatter.format_payment_method_for_receipt(
               :card,
               "4242",
               "visa"
             ) == "**** **** **** 4242"
    end

    test "formats Link wallet with card brand and PAN mask" do
      assert PaymentMethodFormatter.format_payment_method_for_receipt(
               :link,
               "4242",
               "visa"
             ) == "Link · Visa **** **** **** 4242"
    end

    test "formats Link with PAN mask when card brand is missing" do
      assert PaymentMethodFormatter.format_payment_method_for_receipt(
               :link,
               "4242",
               "Link"
             ) == "Link **** **** **** 4242"
    end

    test "formats native Link with account email when no card is exposed" do
      assert PaymentMethodFormatter.format_payment_method_for_receipt(
               :link,
               nil,
               "member@ysc.org"
             ) == "Link · member@ysc.org"
    end
  end
end
