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

    test "normalizes every known Stripe payment type string" do
      assert PaymentMethodFormatter.normalize_payment_type("card") == :card

      assert PaymentMethodFormatter.normalize_payment_type("us_bank_account") ==
               :bank_account

      assert PaymentMethodFormatter.normalize_payment_type("sepa_debit") ==
               :sepa_debit

      assert PaymentMethodFormatter.normalize_payment_type("paypal") == :paypal
      assert PaymentMethodFormatter.normalize_payment_type("affirm") == :affirm
      assert PaymentMethodFormatter.normalize_payment_type("klarna") == :klarna
      assert PaymentMethodFormatter.normalize_payment_type("cashapp") == :cashapp

      assert PaymentMethodFormatter.normalize_payment_type("amazon_pay") ==
               :amazon_pay
    end

    test "falls back to :other for unrecognized strings" do
      assert PaymentMethodFormatter.normalize_payment_type("unknown_wallet") ==
               :other
    end

    test "falls back to :other for non-atom, non-binary input" do
      assert PaymentMethodFormatter.normalize_payment_type(123) == :other
      assert PaymentMethodFormatter.normalize_payment_type(%{}) == :other
    end

    test "passes through atoms unchanged" do
      assert PaymentMethodFormatter.normalize_payment_type(:card) == :card
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

    test "formats Link with card brand only when no PAN is available" do
      assert PaymentMethodFormatter.format_payment_method_for_receipt(
               :link,
               nil,
               "visa"
             ) == "Link · Visa"
    end

    test "formats Link with a fallback brand string when no email or card brand" do
      assert PaymentMethodFormatter.format_payment_method_for_receipt(
               :link,
               nil,
               nil
             ) == "Link"
    end
  end

  describe "extract_payment_method_details_from_charge/1 edge cases" do
    test "falls back to card last4 when wallet omits dynamic_last4" do
      charge = %{
        payment_method_details: %{
          card: %{
            brand: "visa",
            last4: "5555",
            wallet: %{type: "google_pay"}
          }
        }
      }

      assert PaymentMethodFormatter.extract_payment_method_details_from_charge(
               charge
             ) == {"card", "5555", "visa"}
    end

    test "falls back to card last4 with string keys when wallet omits dynamic_last4" do
      charge = %{
        "payment_method_details" => %{
          "card" => %{
            "brand" => "visa",
            "last4" => "6666",
            "wallet" => %{"type" => "google_pay"}
          }
        }
      }

      assert PaymentMethodFormatter.extract_payment_method_details_from_charge(
               charge
             ) == {"card", "6666", "visa"}
    end

    test "returns nils when payment_method_details type is neither card nor link" do
      charge = %{payment_method_details: %{type: "us_bank_account"}}

      assert PaymentMethodFormatter.extract_payment_method_details_from_charge(
               charge
             ) == {nil, nil, nil}
    end

    test "returns nils when charge has no payment_method_details" do
      assert PaymentMethodFormatter.extract_payment_method_details_from_charge(%{}) ==
               {nil, nil, nil}
    end

    test "returns nils for a non-map charge" do
      assert PaymentMethodFormatter.extract_payment_method_details_from_charge(nil) ==
               {nil, nil, nil}

      assert PaymentMethodFormatter.extract_payment_method_details_from_charge(
               "not a charge"
             ) == {nil, nil, nil}
    end
  end

  describe "extract_stripe_pm_last_four_for_type/2" do
    test "reads last4 from us_bank_account" do
      assert PaymentMethodFormatter.extract_stripe_pm_last_four_for_type(
               "us_bank_account",
               %{us_bank_account: %{last4: "4321"}}
             ) == "4321"
    end

    test "returns nil when us_bank_account is missing" do
      assert PaymentMethodFormatter.extract_stripe_pm_last_four_for_type(
               "us_bank_account",
               %{}
             ) == nil
    end

    test "reads last4 from cashapp" do
      assert PaymentMethodFormatter.extract_stripe_pm_last_four_for_type(
               "cashapp",
               %{cashapp: %{last4: "9012"}}
             ) == "9012"
    end

    test "returns nil when cashapp is missing" do
      assert PaymentMethodFormatter.extract_stripe_pm_last_four_for_type(
               "cashapp",
               %{}
             ) == nil
    end

    test "returns nil for unrecognized payment types" do
      assert PaymentMethodFormatter.extract_stripe_pm_last_four_for_type(
               "paypal",
               %{}
             ) == nil
    end
  end

  describe "extract_stripe_pm_display_brand_for_type/2" do
    test "returns Google Pay for google_pay wallet type" do
      stripe_pm = %{card: %{brand: "visa", wallet: %{type: "google_pay"}}}

      assert PaymentMethodFormatter.extract_stripe_pm_display_brand_for_type(
               "card",
               stripe_pm
             ) == "Google Pay"
    end

    test "falls back to card brand for unrecognized wallet types" do
      stripe_pm = %{card: %{brand: "visa", wallet: %{type: "samsung_pay"}}}

      assert PaymentMethodFormatter.extract_stripe_pm_display_brand_for_type(
               "card",
               stripe_pm
             ) == "visa"
    end

    test "reads bank_name from us_bank_account" do
      stripe_pm = %{us_bank_account: %{bank_name: "Chase"}}

      assert PaymentMethodFormatter.extract_stripe_pm_display_brand_for_type(
               "us_bank_account",
               stripe_pm
             ) == "Chase"
    end

    test "returns nil when us_bank_account is missing" do
      assert PaymentMethodFormatter.extract_stripe_pm_display_brand_for_type(
               "us_bank_account",
               %{}
             ) == nil
    end

    test "returns nil for unrecognized payment types" do
      assert PaymentMethodFormatter.extract_stripe_pm_display_brand_for_type(
               "paypal",
               %{}
             ) == nil
    end
  end

  describe "format_payment_method_with_details/3 additional branches" do
    test "defaults card brand label to Card when display brand is missing" do
      assert PaymentMethodFormatter.format_payment_method_with_details(
               "card",
               "1234",
               nil
             ) == "Card ending in 1234"
    end

    test "returns Credit Card when card last four is missing" do
      assert PaymentMethodFormatter.format_payment_method_with_details(
               "card",
               nil,
               "visa"
             ) == "Credit Card"
    end

    test "delegates link formatting" do
      assert PaymentMethodFormatter.format_payment_method_with_details(
               "link",
               "4242",
               "visa"
             ) == "Link · Visa ending in 4242"
    end

    test "formats us_bank_account with a bank name" do
      assert PaymentMethodFormatter.format_payment_method_with_details(
               "us_bank_account",
               "4321",
               "Chase"
             ) == "Chase Account ending in 4321"
    end

    test "returns Bank Account when us_bank_account last four is missing" do
      assert PaymentMethodFormatter.format_payment_method_with_details(
               "us_bank_account",
               nil,
               "Chase"
             ) == "Bank Account"
    end

    test "returns Bank Account when bank_account last four is missing" do
      assert PaymentMethodFormatter.format_payment_method_with_details(
               "bank_account",
               nil,
               "Chase"
             ) == "Bank Account"
    end

    test "delegates to alternative payment method formatting with a last four" do
      assert PaymentMethodFormatter.format_payment_method_with_details(
               "klarna",
               "1234",
               nil
             ) == "Klarna ending in 1234"
    end

    test "delegates to alternative payment method formatting without a last four" do
      assert PaymentMethodFormatter.format_payment_method_with_details(
               "klarna",
               nil,
               nil
             ) == "Klarna"
    end
  end

  describe "format_alternative_payment_method/2" do
    test "formats klarna with and without a last four" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :klarna,
               %{last_four: "1234"}
             ) == "Klarna ending in 1234"

      assert PaymentMethodFormatter.format_alternative_payment_method(:klarna, nil) ==
               "Klarna"
    end

    test "formats amazon_pay" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :amazon_pay,
               nil
             ) == "Amazon Pay"
    end

    test "formats cashapp with and without a last four" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :cashapp,
               %{last_four: "5678"}
             ) == "Cash App ending in 5678"

      assert PaymentMethodFormatter.format_alternative_payment_method(:cashapp, nil) ==
               "Cash App"
    end

    test "formats paypal" do
      assert PaymentMethodFormatter.format_alternative_payment_method(:paypal, nil) ==
               "PayPal"
    end

    test "formats apple_pay" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :apple_pay,
               nil
             ) == "Apple Pay"
    end

    test "formats google_pay" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :google_pay,
               nil
             ) == "Google Pay"
    end

    test "formats link using payment_method fields" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :link,
               %{last_four: "4242", display_brand: "visa"}
             ) == "Link · Visa ending in 4242"
    end

    test "formats us_bank_account and bank_account via bank account formatting" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :us_bank_account,
               %{last_four: "1111", bank_name: "Chase"}
             ) == "Chase Account ending in 1111"

      assert PaymentMethodFormatter.format_alternative_payment_method(
               :bank_account,
               %{last_four: "2222", display_brand: "Ally"}
             ) == "Ally Account ending in 2222"

      assert PaymentMethodFormatter.format_alternative_payment_method(
               :bank_account,
               %{last_four: "3333"}
             ) == "Bank Account ending in 3333"

      assert PaymentMethodFormatter.format_alternative_payment_method(
               :bank_account,
               nil
             ) == "Bank Account"
    end

    test "formats sepa_debit with and without a last four" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :sepa_debit,
               %{last_four: "9999"}
             ) == "SEPA Debit ending in 9999"

      assert PaymentMethodFormatter.format_alternative_payment_method(
               :sepa_debit,
               nil
             ) == "SEPA Debit"
    end

    test "formats card with and without a last four" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :card,
               %{last_four: "1234", display_brand: "mastercard"}
             ) == "Mastercard ending in 1234"

      assert PaymentMethodFormatter.format_alternative_payment_method(:card, nil) ==
               "Credit Card"
    end

    test "title-cases unknown atom types as a fallback label" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :unknown_wallet,
               nil
             ) == "Unknown Wallet"
    end

    test "normalizes a binary type before dispatching" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               "klarna",
               %{last_four: "1234"}
             ) == "Klarna ending in 1234"
    end

    test "returns a generic label for a non-atom, non-binary type" do
      assert PaymentMethodFormatter.format_alternative_payment_method(123, nil) ==
               "Payment Method"
    end

    test "humanizes an unrecognized atom type" do
      assert PaymentMethodFormatter.format_alternative_payment_method(
               :some_new_method,
               nil
             ) == "Some New Method"
    end
  end

  describe "format_link_payment_method/2" do
    test "formats with card brand and last four" do
      assert PaymentMethodFormatter.format_link_payment_method("4242", "visa") ==
               "Link · Visa ending in 4242"
    end

    test "formats with last four only when brand is Link itself" do
      assert PaymentMethodFormatter.format_link_payment_method("4242", "Link") ==
               "Link ending in 4242"
    end

    test "formats with card brand only when last four is missing" do
      assert PaymentMethodFormatter.format_link_payment_method(nil, "visa") ==
               "Link · Visa"
    end

    test "falls back to bare Link when brand and last four are missing" do
      assert PaymentMethodFormatter.format_link_payment_method(nil, nil) == "Link"
    end
  end

  describe "payment_brand_label/1 additional brands" do
    test "maps amex" do
      assert PaymentMethodFormatter.payment_brand_label("amex") == "Amex"
    end

    test "maps american_express" do
      assert PaymentMethodFormatter.payment_brand_label("american_express") ==
               "American Express"
    end

    test "maps mastercard" do
      assert PaymentMethodFormatter.payment_brand_label("mastercard") == "Mastercard"
    end
  end

  describe "payment_details_from_payment_intent/2 richer-details tie-breaking" do
    defmodule RankStripeClientStub do
      def retrieve_payment_method("pm_unknown"), do: {:error, :not_found}
      def retrieve_charge("ch_unknown", _opts), do: {:error, :not_found}
    end

    test "prefers charge details when charge rank exceeds payment method rank" do
      payment_intent = %{
        payment_method: %{type: "card", card: %{brand: "visa"}},
        latest_charge: %{
          payment_method_details: %{
            type: "link",
            link: %{email: "member@ysc.org"}
          }
        }
      }

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               RankStripeClientStub
             ) == {"link", nil, "member@ysc.org"}
    end

    test "prefers payment method details when its rank is at least as high" do
      payment_intent = %{
        payment_method: %{type: "link", link: %{email: "member@ysc.org"}},
        latest_charge: %{
          payment_method_details: %{card: %{brand: "visa"}}
        }
      }

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               RankStripeClientStub
             ) == {"link", nil, "member@ysc.org"}
    end

    test "treats an empty display brand string as unranked" do
      payment_intent = %{payment_method: %{type: "card", card: %{brand: ""}}}

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               RankStripeClientStub
             ) == {"card", nil, ""}
    end

    test "returns nils when retrieving the payment method by id fails" do
      payment_intent = %{payment_method: "pm_unknown"}

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               RankStripeClientStub
             ) == {nil, nil, nil}
    end

    test "returns nils when retrieving the charge by id fails" do
      payment_intent = %{payment_method: nil, latest_charge: "ch_unknown"}

      assert PaymentMethodFormatter.payment_details_from_payment_intent(
               payment_intent,
               RankStripeClientStub
             ) == {nil, nil, nil}
    end
  end
end
