defmodule YscWeb.PaymentMethodLogoTest do
  use ExUnit.Case, async: true

  alias Ysc.Payments.PaymentMethod
  alias YscWeb.PaymentMethodLogo

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
  end

  describe "path_for_stripe_summary/2" do
    test "returns Link logo for stripe summary type link" do
      assert PaymentMethodLogo.path_for_stripe_summary(:link, nil) ==
               "/images/cards/link.png"
    end
  end
end
