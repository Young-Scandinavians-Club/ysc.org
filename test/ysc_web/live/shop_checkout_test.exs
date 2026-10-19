defmodule YscWeb.ShopCheckoutTest do
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Mox
  import Phoenix.LiveViewTest
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Cart, Order, Orders}
  alias Ysc.Printful.{ClientMock, Error}
  alias Ysc.Repo
  alias Ysc.StripeMock

  setup :verify_on_exit!

  setup %{conn: conn} do
    Ysc.Ledgers.ensure_basic_accounts()

    originals =
      for key <- [:stripe_client, :quickbooks_client],
          do: {key, Application.get_env(:ysc, key)}

    Application.put_env(:ysc, :stripe_client, StripeMock)
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    on_exit(fn ->
      Enum.each(originals, fn {k, v} -> Application.put_env(:ysc, k, v) end)
    end)

    stub_quickbooks_sync!()

    stub(ClientMock, :get_order_by_external_id, fn _ ->
      {:error, %Error{type: :not_found, message: "x"}}
    end)

    stub(ClientMock, :create_order, fn _, true ->
      {:ok, %{"id" => 7, "status" => "pending"}}
    end)

    member =
      member_fixture()
      |> Ecto.Changeset.change(
        stripe_id: "cus_checkout",
        phone_number: "+14155550100"
      )
      |> Repo.update!()

    tee = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})
    sticker = variant_fixture(nil, %{retail_price: Money.new(:USD, "3.50")})
    cart_lines_fixture(member, [{tee, 2}, {sticker, 4}])

    %{conn: log_in_user(conn, member), member: member, tee: tee}
  end

  @address %{
    "name" => "Ada Lovelace",
    "address1" => "1 Market St",
    "city" => "San Francisco",
    "state_code" => "CA",
    "zip" => "94105",
    "phone" => "415-555-0100"
  }

  defp rates do
    {:ok,
     [
       %{
         "id" => "EXPRESS",
         "name" => "Express",
         "rate" => "14.50",
         "currency" => "USD",
         "minDeliveryDays" => 1,
         "maxDeliveryDays" => 2
       },
       %{
         "id" => "STANDARD",
         "name" => "Flat Rate",
         "rate" => "5.95",
         "currency" => "USD",
         "minDeliveryDays" => 3,
         "maxDeliveryDays" => 5
       }
     ]}
  end

  defp submit_address(view, overrides \\ %{}) do
    view
    |> form("#address-form", address: Map.merge(@address, overrides))
    |> render_submit()

    render_async(view)
  end

  defp to_shipping(view) do
    stub(ClientMock, :shipping_rates, fn _, _ -> rates() end)
    submit_address(view)
  end

  defp stub_payment_intent do
    stub(StripeMock, :create_payment_intent, fn params, _ ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_checkout",
         status: "requires_payment_method",
         amount: params.amount,
         client_secret: "pi_checkout_secret_abc"
       }}
    end)
  end

  test "an empty cart goes back to the cart page", %{conn: conn, member: member} do
    Cart.clear(member)

    assert {:error, {:live_redirect, %{to: "/shop/cart"}}} =
             live(conn, ~p"/shop/checkout")
  end

  describe "address step" do
    test "starts with the member's details and the order summary", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")

      assert has_element?(view, "#checkout-address")
      assert has_element?(view, "#summary-subtotal", "$64.00")
      assert has_element?(view, "#summary-shipping", "Calculated next")
      refute has_element?(view, "#summary-total")
    end

    test "shows validation errors and does not call Printful", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")

      html =
        view
        |> form("#address-form",
          address: %{"name" => "", "address1" => "", "zip" => "9"}
        )
        |> render_change()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"

      view
      |> form("#address-form",
        address: %{"name" => "", "address1" => "", "zip" => "9"}
      )
      |> render_submit()

      assert has_element?(view, "#checkout-address")
      refute has_element?(view, "#checkout-shipping")
    end

    test "a rejected address stays on the form with Printful's reason", %{
      conn: conn
    } do
      stub(ClientMock, :shipping_rates, fn _, _ ->
        {:error,
         %Error{
           type: :invalid,
           status: 400,
           message: "Zip code does not match state"
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      submit_address(view)

      assert has_element?(view, "#checkout-address")

      assert has_element?(
               view,
               "#address-error",
               "Zip code does not match state"
             )
    end

    test "a Printful outage asks the member to retry", %{conn: conn} do
      stub(ClientMock, :shipping_rates, fn _, _ ->
        {:error, %Error{type: :server, status: 503, message: "down"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      submit_address(view)

      assert has_element?(view, "#address-error", "try again")
      assert has_element?(view, "#checkout-address")
    end
  end

  describe "delivery estimates in the shipping step" do
    defp dated_rates do
      {:ok, rates} = rates()
      min = Date.utc_today() |> Date.add(6)
      max = Date.add(min, 2)

      {:ok,
       Enum.map(rates, fn
         %{"id" => "STANDARD"} = rate ->
           Map.merge(rate, %{
             "minDeliveryDate" => Date.to_iso8601(min),
             "maxDeliveryDate" => Date.to_iso8601(max)
           })

         rate ->
           rate
       end)}
    end

    test "each option with dates says when it should arrive", %{conn: conn} do
      stub(ClientMock, :shipping_rates, fn _, _ -> dated_rates() end)
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      submit_address(view)

      assert has_element?(
               view,
               "#shipping-timing-STANDARD",
               "Estimated delivery"
             )

      assert has_element?(
               view,
               "#shipping-timing-STANDARD",
               Ysc.Merch.Shipping.delivery_estimate(%{
                 min_date: Date.add(Date.utc_today(), 6),
                 max_date: Date.add(Date.utc_today(), 8)
               })
             )
    end

    test "without dates it falls back to the business-day window", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)

      assert has_element?(
               view,
               "#shipping-timing-STANDARD",
               "3-5 business days"
             )

      refute has_element?(
               view,
               "#shipping-timing-STANDARD",
               "Estimated delivery"
             )
    end
  end

  describe "shipping step" do
    test "offers Printful's options cheapest first, preselected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)

      assert has_element?(view, "#checkout-address-summary", "Ada Lovelace")
      assert has_element?(view, "#shipping-option-STANDARD input[checked]")
      assert has_element?(view, "#shipping-option-EXPRESS")
      assert has_element?(view, "#summary-shipping", "$5.95")
      assert has_element?(view, "#summary-total", "$69.95")
    end

    test "choosing a method updates the total", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)

      view |> element("#shipping-option-EXPRESS input") |> render_click()
      assert has_element?(view, "#summary-total", "$78.50")
    end

    test "the address can be edited", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)

      view |> element("#edit-address") |> render_click()
      assert has_element?(view, "#address-form")
      refute has_element?(view, "#checkout-shipping")
    end

    test "ignores a shipping method Printful never offered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)

      render_click(view, "select_shipping", %{"id" => "FREE_OVERNIGHT"})
      assert has_element?(view, "#summary-total", "$69.95")
    end
  end

  describe "payment step" do
    test "creates a pending order and opens payment for the exact total", %{
      conn: conn,
      member: member
    } do
      expect(StripeMock, :create_payment_intent, fn params, _ ->
        # 2 x 25.00 + 4 x 3.50 + 5.95 shipping
        assert params.amount == 6995

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_checkout",
           status: "requires_payment_method",
           amount: 6995,
           client_secret: "pi_checkout_secret_abc"
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      assert [%Order{status: :pending} = order] = Repo.all(Order)
      assert order.user_id == member.id
      assert order.payment_intent_id == "pi_checkout"
      assert Money.equal?(order.total_amount, Money.new(:USD, "69.95"))

      assert has_element?(view, "#checkout-shipping-summary", "Flat Rate")

      assert has_element?(
               view,
               ~s(#stripe-payment-container[data-client-secret="pi_checkout_secret_abc"])
             )

      assert has_element?(
               view,
               ~s(#stripe-payment-container[data-return-path="/shop/orders/#{order.id}/confirmation"])
             )

      assert has_element?(view, "#submit-payment", "$69.95")
    end

    test "going back and returning reuses the same order", %{conn: conn} do
      stub_payment_intent()

      stub(StripeMock, :retrieve_payment_intent, fn _, _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_checkout",
           status: "requires_payment_method",
           amount: 6995,
           client_secret: "pi_checkout_secret_abc"
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      view |> element("#edit-shipping") |> render_click()
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      assert Repo.aggregate(Order, :count) == 1
    end

    test "Finding 92: payment re-quotes shipping for the current cart, not the earlier quote",
         %{
           conn: conn,
           member: member
         } do
      extra = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})

      stub(ClientMock, :shipping_rates, fn _, items ->
        quantity = Enum.reduce(items, 0, &(&1.quantity + &2))
        rate = if quantity <= 6, do: "5.95", else: "24.00"

        {:ok,
         [
           %{
             "id" => "STANDARD",
             "name" => "Flat Rate",
             "rate" => rate,
             "currency" => "USD"
           }
         ]}
      end)

      expect(StripeMock, :create_payment_intent, fn params, _ ->
        # Original cart $64.00 + extra $25.00 + requoted shipping $24.00
        assert params.amount == 11_300

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_checkout",
           status: "requires_payment_method",
           amount: 11_300,
           client_secret: "pi_checkout_secret_abc"
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      submit_address(view)

      assert has_element?(view, "#summary-shipping", "$5.95")
      assert has_element?(view, "#summary-total", "$69.95")

      assert {:ok, _} = Cart.add(member, extra.id, 1)

      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      assert [%Order{status: :pending} = order] = Repo.all(Order)
      assert Money.equal?(order.shipping_amount, Money.new(:USD, "24.00"))
      assert Money.equal?(order.subtotal, Money.new(:USD, "89.00"))
      assert Money.equal?(order.total_amount, Money.new(:USD, "113.00"))
      assert has_element?(view, "#submit-payment", "$113.00")
    end

    test "a Stripe failure keeps the member on the shipping step", %{conn: conn} do
      expect(StripeMock, :create_payment_intent, fn _, _ ->
        {:error,
         %Stripe.Error{source: :stripe, code: :api_error, message: "boom"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      assert has_element?(view, "#shipping-error")
      refute has_element?(view, "#checkout-payment")
    end

    test "a processing Intent waits on confirmation instead of opening payment",
         %{
           conn: conn,
           member: member
         } do
      {:ok, order} =
        Orders.create_pending_purchase(
          member,
          Cart.list(member),
          shipping_address_fixture(),
          shipping_option_fixture()
        )

      {:ok, _} = Orders.attach_payment_intent(order, "pi_processing")

      # Same cart: reusable pending + ensure_payment_intent reuses processing.
      expect(StripeMock, :retrieve_payment_intent, fn "pi_processing", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_processing",
           status: "processing",
           amount: 6995
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()

      assert_redirect(
        view,
        ~p"/shop/orders/#{order.id}/confirmation"
      )

      assert %Order{payment_intent_id: "pi_processing", status: :pending} =
               Orders.get_order!(order.id)
    end

    test "a processing Intent blocks a second checkout after the cart changes",
         %{
           conn: conn,
           member: member
         } do
      extra = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})

      {:ok, order} =
        Orders.create_pending_purchase(
          member,
          Cart.list(member),
          shipping_address_fixture(),
          shipping_option_fixture()
        )

      {:ok, _} = Orders.attach_payment_intent(order, "pi_processing")
      assert {:ok, _} = Cart.add(member, extra.id, 1)

      expect(StripeMock, :retrieve_payment_intent, fn "pi_processing", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_processing",
           status: "processing",
           amount: 6995
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      assert has_element?(view, "#shipping-error", "still processing")
      refute has_element?(view, "#checkout-payment")
      assert Repo.aggregate(Order, :count) == 1
    end

    test "an unpaid prior Intent is Stripe-canceled when the cart changes", %{
      conn: conn,
      member: member
    } do
      extra = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})

      {:ok, order} =
        Orders.create_pending_purchase(
          member,
          Cart.list(member),
          shipping_address_fixture(),
          shipping_option_fixture()
        )

      {:ok, _} = Orders.attach_payment_intent(order, "pi_open")
      assert {:ok, _} = Cart.add(member, extra.id, 1)

      expect(StripeMock, :retrieve_payment_intent, fn "pi_open", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_open",
           status: "requires_payment_method",
           amount: 6995
         }}
      end)

      expect(StripeMock, :cancel_payment_intent, fn "pi_open", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_open",
           status: "canceled",
           amount: 6995
         }}
      end)

      stub_payment_intent()

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      assert has_element?(view, "#checkout-payment")
      assert Orders.get_order!(order.id).status == :canceled

      assert [%Order{status: :pending}, %Order{status: :canceled}] =
               Enum.sort_by(Repo.all(Order), & &1.status, :desc)
    end

    test "a prior Intent that succeeds between retrieve and cancel blocks a second checkout",
         %{
           conn: conn,
           member: member
         } do
      extra = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})

      {:ok, order} =
        Orders.create_pending_purchase(
          member,
          Cart.list(member),
          shipping_address_fixture(),
          shipping_option_fixture()
        )

      {:ok, _} = Orders.attach_payment_intent(order, "pi_raced_paid")
      assert {:ok, _} = Cart.add(member, extra.id, 1)

      expect(StripeMock, :retrieve_payment_intent, fn "pi_raced_paid", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_raced_paid",
           status: "requires_payment_method",
           amount: 6995
         }}
      end)

      expect(StripeMock, :cancel_payment_intent, fn "pi_raced_paid", _ ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :payment_intent_unexpected_state,
           message: "cannot cancel",
           extra: %{}
         }}
      end)

      expect(StripeMock, :retrieve_payment_intent, fn "pi_raced_paid", opts ->
        assert opts[:expand] == ["latest_charge"]

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_raced_paid",
           status: "succeeded",
           amount: 6995
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      assert has_element?(view, "#shipping-error", "still processing")
      refute has_element?(view, "#checkout-payment")
      assert Repo.aggregate(Order, :count) == 1
      assert Orders.get_order!(order.id).status == :pending
      assert Orders.get_order!(order.id).payment_intent_id == "pi_raced_paid"
    end

    test "a Stripe outage while checking the stored Intent blocks a second checkout",
         %{
           conn: conn,
           member: member
         } do
      extra = variant_fixture(nil, %{retail_price: Money.new(:USD, "25")})

      {:ok, order} =
        Orders.create_pending_purchase(
          member,
          Cart.list(member),
          shipping_address_fixture(),
          shipping_option_fixture()
        )

      {:ok, _} = Orders.attach_payment_intent(order, "pi_outage")
      assert {:ok, _} = Cart.add(member, extra.id, 1)

      expect(StripeMock, :retrieve_payment_intent, fn "pi_outage", _ ->
        {:error,
         %Stripe.Error{source: :stripe, code: :api_error, message: "down"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      assert has_element?(view, "#shipping-error", "still processing")
      refute has_element?(view, "#checkout-payment")
      assert Repo.aggregate(Order, :count) == 1
      assert Orders.get_order!(order.id).status == :pending
    end

    test "payment-success settles the order and opens the confirmation page", %{
      conn: conn
    } do
      stub_payment_intent()
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      [order] = Repo.all(Order)

      expect(StripeMock, :retrieve_payment_intent, fn "pi_checkout", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_checkout",
           status: "succeeded",
           amount: 6995,
           metadata: %{"merch_order_id" => order.id}
         }}
      end)

      view
      |> element("#stripe-payment-container")
      |> render_hook("payment-success", %{"payment_intent_id" => "pi_checkout"})

      assert_redirect(view, ~p"/shop/orders/#{order.id}/confirmation")

      assert %Order{status: :submitted} = Orders.get_order!(order.id)
      assert Cart.list(order |> Repo.preload(:user) |> Map.fetch!(:user)) == []
    end

    test "the Stripe element readiness events are accepted", %{conn: conn} do
      stub_payment_intent()
      {:ok, view, _html} = live(conn, ~p"/shop/checkout")
      to_shipping(view)
      view |> element("#continue-to-payment") |> render_click()
      render_async(view)

      assert has_element?(view, "#submit-payment[disabled]")

      view
      |> element("#stripe-payment-container")
      |> render_hook("stripe-payment-element-ready", %{})

      refute has_element?(view, "#submit-payment[disabled]")
    end
  end
end
