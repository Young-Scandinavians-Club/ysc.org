defmodule YscWeb.UserSettingsMerchPaymentsTest do
  @moduledoc """
  Merch purchases show up in "My Bookings & Payments" and have their own filter.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.MerchFixtures

  alias Ysc.Ledgers

  setup %{conn: conn} do
    member = member_fixture()
    order = purchase_order_fixture(member, :submitted)

    merch_payment = record_payment!(member, :merch, order.id, "Merch")
    donation_payment = record_payment!(member, :donation, nil, "Donation")

    %{
      conn: log_in_user(conn, member),
      member: member,
      order: order,
      merch_payment: merch_payment,
      donation_payment: donation_payment
    }
  end

  defp record_payment!(user, entity_type, entity_id, description) do
    {:ok, {payment, _, _}} =
      Ledgers.process_payment(%{
        user_id: user.id,
        amount: Money.new(:USD, "69.95"),
        entity_type: entity_type,
        entity_id: entity_id,
        external_payment_id:
          "pi_merch_hist_#{System.unique_integer([:positive])}",
        stripe_fee: Money.new(:USD, "2.30"),
        description: description,
        property: nil,
        payment_method_id: nil
      })

    payment
  end

  describe "ledger listing" do
    test "merch payments carry their order", %{
      member: member,
      order: order,
      merch_payment: payment
    } do
      {items, 2} = Ledgers.list_user_payments_paginated(member.id)

      merch = Enum.find(items, &(&1.type == :merch))
      assert merch.payment.id == payment.id
      assert merch.merch_order.id == order.id
      assert merch.description == "Merch order #{order.reference_id}"
    end

    test "the merch filter only returns merch", %{member: member} do
      {items, 1} =
        Ledgers.list_user_payments_paginated(member.id, 1, 20, filter: :merch)

      assert [%{type: :merch}] = items
    end

    test "other filters leave merch out", %{member: member} do
      {items, 1} =
        Ledgers.list_user_payments_paginated(member.id, 1, 20,
          filter: :donations
        )

      assert [%{type: :donation}] = items
    end
  end

  describe "payments tab" do
    test "lists the merch order next to other payments", %{
      conn: conn,
      order: order
    } do
      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render_async(view)

      assert has_element?(view, "#payment-merch-#{order.id}")

      assert has_element?(
               view,
               "#payment-merch-#{order.id}",
               order.reference_id
             )

      assert has_element?(view, "#payment-merch-#{order.id}", "Club Tee")
    end

    test "the Merch filter narrows the list to merch orders", %{
      conn: conn,
      order: order,
      donation_payment: donation
    } do
      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render_async(view)

      assert has_element?(view, "#payment-donation-#{donation.id}")

      view |> element("#payment-filter-merch") |> render_click()

      assert has_element?(view, "#payment-merch-#{order.id}")
      refute has_element?(view, "#payment-donation-#{donation.id}")
    end

    test "a merch row opens the shop order", %{conn: conn, order: order} do
      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render_async(view)

      view |> element("#payment-merch-#{order.id}") |> render_click()
      assert_redirect(view, ~p"/shop/orders/#{order.id}")
    end
  end
end
