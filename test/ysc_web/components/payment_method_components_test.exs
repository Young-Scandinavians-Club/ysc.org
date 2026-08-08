defmodule YscWeb.PaymentMethodComponentsTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.PaymentMethodComponents

  describe "stored_payment_method_display/1" do
    test "renders card pan mask and expiration for cards" do
      assigns = %{
        payment_method: %{
          type: :card,
          display_brand: "visa",
          last_four: "4242",
          exp_month: 3,
          exp_year: 2028
        }
      }

      heex = ~H"""
      <.stored_payment_method_display payment_method={@payment_method} />
      """

      html = rendered_to_string(heex)

      assert html =~ "/images/cards/visa.png"
      assert html =~ "**** **** **** 4242"
      assert html =~ "Expires 03 / 2028"
    end

    test "renders Link display text and expiration" do
      assigns = %{
        payment_method: %{
          type: :link,
          display_brand: "visa",
          last_four: "4242",
          exp_month: 12,
          exp_year: 2027
        }
      }

      heex = ~H"""
      <.stored_payment_method_display payment_method={@payment_method} />
      """

      html = rendered_to_string(heex)

      assert html =~ "/images/cards/link.png"
      assert html =~ "Link · Visa ending in 4242"
      assert html =~ "Expires 12 / 2027"
    end

    test "renders bank account details with bank icon fallback" do
      assigns = %{
        payment_method: %{
          type: :bank_account,
          bank_name: "Chase",
          last_four: "6789",
          account_type: "checking"
        }
      }

      heex = ~H"""
      <.stored_payment_method_display payment_method={@payment_method} />
      """

      html = rendered_to_string(heex)

      assert html =~ "hero-building-library"
      refute html =~ "/images/cards/"
      assert html =~ "Chase ••••6789"
      assert html =~ "checking"
      refute html =~ "Expires"
    end

    test "renders generic credit card icon when no logo is available" do
      assigns = %{
        payment_method: %{
          type: :card,
          display_brand: nil,
          last_four: nil
        }
      }

      heex = ~H"""
      <.stored_payment_method_display payment_method={@payment_method} />
      """

      html = rendered_to_string(heex)

      assert html =~ "hero-credit-card"
      assert html =~ "Credit Card"
      refute html =~ "Expires"
    end

    test "renders bank account fallback label without last four" do
      assigns = %{
        payment_method: %{
          type: :bank_account,
          bank_name: nil,
          last_four: nil,
          account_type: nil
        }
      }

      heex = ~H"""
      <.stored_payment_method_display payment_method={@payment_method} />
      """

      html = rendered_to_string(heex)

      assert html =~ "Bank Account"
      assert html =~ "hero-building-library"
    end
  end
end
