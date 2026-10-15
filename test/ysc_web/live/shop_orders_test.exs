defmodule YscWeb.ShopOrdersTest do
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Mox
  import Phoenix.LiveViewTest
  import Ysc.MerchFixtures

  alias Ysc.Merch.{Order, Orders}
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

    member = member_fixture()
    %{conn: log_in_user(conn, member), member: member}
  end

  defp order_for(member, status, payment_intent_id \\ nil) do
    lines =
      cart_lines_fixture(member, [
        {variant_fixture(nil, %{
           retail_price: Money.new(:USD, "25"),
           name: "Club Tee / Black / M"
         }), 2}
      ])

    {:ok, order} =
      Orders.create_pending_purchase(
        member,
        lines,
        shipping_address_fixture(),
        shipping_option_fixture()
      )

    order
    |> Ecto.Changeset.change(
      status: status,
      payment_intent_id: payment_intent_id
    )
    |> Repo.update!()
  end

  defp succeeded(order) do
    %Stripe.PaymentIntent{
      id: order.payment_intent_id,
      status: "succeeded",
      amount: 5595,
      metadata: %{"merch_order_id" => order.id}
    }
  end

  describe "order page" do
    test "shows the receipt, address and status", %{conn: conn, member: member} do
      order = order_for(member, :shipped)
      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{order.id}")

      assert has_element?(view, "#order-summary-#{order.id}", "Club Tee")
      assert has_element?(view, "#order-summary-#{order.id}", "Black · M")
      assert has_element?(view, "#order-reference", order.reference_id)

      assert has_element?(view, "#order-summary-#{order.id}", "$55.95")
      assert has_element?(view, "#order-ship-to", "Ada Lovelace")
      assert has_element?(view, "#order-ship-to", "San Francisco, CA 94105")

      assert has_element?(
               view,
               "#order-progress #progress-shipped .bg-green-600"
             )

      refute has_element?(
               view,
               "#order-progress #progress-delivered .bg-green-600"
             )

      refute has_element?(view, "#order-banner-confirmed")
    end

    test "only the owner can see an order", %{conn: conn, member: member} do
      order = order_for(member, :shipped)
      other = log_in_user(build_conn(), member_fixture())

      assert {:error, {:live_redirect, %{to: "/shop/orders"}}} =
               live(other, ~p"/shop/orders/#{order.id}")

      assert {:error, {:live_redirect, %{to: "/shop/orders"}}} =
               live(conn, ~p"/shop/orders/#{Ecto.ULID.generate()}")

      assert {:error, {:live_redirect, %{to: "/shop/orders"}}} =
               live(conn, ~p"/shop/orders/garbage")
    end

    test "failed orders explain the problem", %{conn: conn, member: member} do
      order = order_for(member, :failed)
      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{order.id}")

      assert has_element?(view, "#order-banner-failed")
      refute has_element?(view, "#order-progress")
    end

    test "canceled and refunded orders are labeled", %{
      conn: conn,
      member: member
    } do
      canceled = order_for(member, :canceled)
      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{canceled.id}")
      assert has_element?(view, "#order-banner-closed", "canceled")

      refunded = order_for(member, :refunded)
      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{refunded.id}")
      assert has_element?(view, "#order-banner-closed", "refunded")
    end

    test "a lapsed member can still open their order", %{conn: conn} do
      lapsed = Ysc.AccountsFixtures.user_fixture()
      order = order_for(lapsed, :delivered)

      {:ok, view, _html} =
        live(log_in_user(conn, lapsed), ~p"/shop/orders/#{order.id}")

      assert has_element?(
               view,
               "#order-progress #progress-delivered .bg-green-600"
             )
    end
  end

  describe "tracking" do
    test "lists each parcel with a safe tracking link", %{
      conn: conn,
      member: member
    } do
      order = order_for(member, :shipped)

      shipped =
        %Ysc.Merch.Shipment{}
        |> Ysc.Merch.Shipment.changeset(%{
          order_id: order.id,
          printful_shipment_id: 91_001,
          carrier: "USPS",
          service: "Priority Mail",
          tracking_number: "9400111899223197428490",
          tracking_url: "https://tools.usps.com/track?x=1",
          shipped_at: ~U[2026-10-10 12:00:00Z]
        })
        |> Repo.insert!()

      unsafe =
        %Ysc.Merch.Shipment{}
        |> Ysc.Merch.Shipment.changeset(%{
          order_id: order.id,
          printful_shipment_id: 91_002,
          carrier: "FedEx",
          tracking_url: "javascript:alert(1)",
          status: :delivered,
          shipped_at: ~U[2026-10-11 12:00:00Z],
          delivered_at: ~U[2026-10-14 12:00:00Z]
        })
        |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{order.id}")

      assert has_element?(view, "#shipment-#{shipped.id}", "USPS")
      assert has_element?(view, "#shipment-#{shipped.id}", "Shipped Oct 10")

      assert has_element?(
               view,
               "#shipment-#{shipped.id}",
               "9400111899223197428490"
             )

      assert has_element?(
               view,
               ~s(#track-#{shipped.id}[href="https://tools.usps.com/track?x=1"][target="_blank"][rel~="noopener"])
             )

      assert has_element?(view, "#shipment-#{unsafe.id}", "Delivered Oct 14")
      refute has_element?(view, "#track-#{unsafe.id}")
    end

    test "has no tracking section before anything ships", %{
      conn: conn,
      member: member
    } do
      order = order_for(member, :submitted)
      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{order.id}")
      refute has_element?(view, "#order-tracking")
    end

    test "a returned parcel says so", %{conn: conn, member: member} do
      order = order_for(member, :shipped)

      shipment =
        %Ysc.Merch.Shipment{}
        |> Ysc.Merch.Shipment.changeset(%{
          order_id: order.id,
          printful_shipment_id: 91_003,
          status: :returned
        })
        |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{order.id}")

      assert has_element?(
               view,
               "#shipment-#{shipment.id}",
               "Returned to sender"
             )
    end
  end

  describe "confirmation (Stripe return page)" do
    test "settles the order from Stripe's record and thanks the member", %{
      conn: conn,
      member: member
    } do
      order = order_for(member, :pending, "pi_return")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_return", _ ->
        {:ok, succeeded(order)}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{order.id}/confirmation")
      render(view)

      assert has_element?(view, "#order-banner-confirmed", "Thank you")
      assert %Order{status: :submitted} = Orders.get_order!(order.id)
      assert has_element?(view, "#order-progress #progress-paid .bg-green-600")
    end

    test "ignores the query string and trusts only Stripe", %{
      conn: conn,
      member: member
    } do
      order = order_for(member, :pending, "pi_real")

      expect(StripeMock, :retrieve_payment_intent, fn "pi_real", _ ->
        {:ok, succeeded(order)}
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/shop/orders/#{order.id}/confirmation?payment_intent=pi_attacker&redirect_status=succeeded"
        )

      render(view)
      assert %Order{status: :submitted} = Orders.get_order!(order.id)
    end

    test "keeps checking while Stripe is still processing", %{
      conn: conn,
      member: member
    } do
      order = order_for(member, :pending, "pi_slow")

      stub(StripeMock, :retrieve_payment_intent, fn "pi_slow", _ ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_slow",
           status: "processing",
           amount: 5595,
           metadata: %{"merch_order_id" => order.id}
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{order.id}/confirmation")
      render(view)

      assert has_element?(
               view,
               "#order-banner-pending",
               "Confirming your payment"
             )

      assert Orders.get_order!(order.id).status == :pending
    end

    test "an order paid via the webhook first just shows as confirmed", %{
      conn: conn,
      member: member
    } do
      order = order_for(member, :submitted, "pi_hook")
      {:ok, view, _html} = live(conn, ~p"/shop/orders/#{order.id}/confirmation")

      assert has_element?(view, "#order-banner-confirmed")
    end
  end

  describe "order history" do
    test "lists purchases newest first and hides unfinished checkouts", %{
      conn: conn,
      member: member
    } do
      shipped = order_for(member, :shipped)
      _pending = order_for(member, :pending)

      {:ok, view, _html} = live(conn, ~p"/shop/orders")

      assert has_element?(view, "#order-#{shipped.id}", shipped.reference_id)
      assert has_element?(view, "#order-#{shipped.id}", "Shipped")
      assert has_element?(view, "#order-#{shipped.id}", "$55.95")
      assert has_element?(view, "#orders-list li", shipped.reference_id)
      refute has_element?(view, "#orders-empty")
    end

    test "never shows another member's orders", %{conn: conn} do
      other = member_fixture()
      theirs = order_for(other, :shipped)

      {:ok, view, _html} = live(conn, ~p"/shop/orders")
      assert has_element?(view, "#orders-empty")
      refute has_element?(view, "#order-#{theirs.id}")
    end
  end
end
