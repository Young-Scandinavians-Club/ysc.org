defmodule YscWeb.AdminMoneyLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Mox
  import Ecto.Query

  alias Ysc.Ledgers
  alias Ysc.LedgersFixtures
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp setup_qb_mocks(_context) do
    Application.put_env(:ysc, :quickbooks_client, Ysc.Quickbooks.ClientMock)

    Application.put_env(:ysc, :quickbooks,
      client_id: "test_client_id",
      client_secret: "test_client_secret",
      company_id: "test_company_id",
      access_token: "test_access_token",
      refresh_token: "test_refresh_token",
      event_item_id: "event_item_123",
      donation_item_id: "donation_item_123",
      bank_account_id: "bank_account_123",
      stripe_account_id: "stripe_account_123"
    )

    stub(Ysc.Quickbooks.ClientMock, :create_deposit, fn _params, _opts ->
      {:ok, %{"Id" => "qb_deposit_test", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_customer, fn _params ->
      {:ok, %{"Id" => "qb_customer_test"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_sales_receipt, fn _params, _opts ->
      {:ok, %{"Id" => "qb_sr_test", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_account_by_name, fn _name ->
      {:ok, "revenue_account_test"}
    end)

    stub(Ysc.Quickbooks.ClientMock, :get_or_create_item, fn _name, _opts ->
      {:ok, "qb_item_test"}
    end)

    stub(Ysc.Quickbooks.ClientMock, :get_item_by_id, fn _id ->
      {:ok,
       %{
         "Id" => "qb_item_test",
         "IncomeAccountRef" => %{"value" => "revenue_account_test"}
       }}
    end)

    stub(Ysc.Quickbooks.ClientMock, :create_refund_receipt, fn _params, _opts ->
      {:ok, %{"Id" => "qb_rr_test", "TotalAmt" => "0.00"}}
    end)

    stub(Ysc.Quickbooks.ClientMock, :query_class_by_name, fn _name ->
      {:ok, "qb_class_test"}
    end)

    :ok
  end

  defp completed_ticket_order_with_payment! do
    user = user_fixture()

    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

    event = event_fixture()
    tier = ticket_tier_fixture(%{event_id: event.id})

    {:ok, order} =
      Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})

    {:ok, {payment, _transaction, _entries}} =
      Ledgers.process_event_payment_with_donations(%{
        user_id: user.id,
        total_amount: order.total_amount,
        event_amount: order.total_amount,
        donation_amount: Money.new(0, :USD),
        event_id: event.id,
        external_payment_id:
          "pi_admin_refund_#{System.unique_integer([:positive])}",
        stripe_fee: Money.new(320, :USD),
        description: "Event tickets",
        payment_method_id: nil
      })

    {:ok, completed} = Tickets.complete_ticket_order(order, payment.id)

    from(t in Ysc.Events.Ticket, where: t.ticket_order_id == ^order.id)
    |> Repo.update_all(set: [status: :confirmed])

    %{payment: payment, ticket_order: completed}
  end

  describe "Admin Money" do
    setup [:create_admin]

    test "renders money management page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/money")
      assert html =~ "Money Management"
      assert html =~ "Account Balances"
      assert html =~ "Recent Payments"
    end

    test "toggles sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      assert render(view) =~ "Ledger Entries"

      # Initially collapsed sections might not show their content
      refute render(view) =~ "Debit/Credit"

      view
      |> element("button", "Ledger Entries")
      |> render_click()

      assert render(view) =~ "Debit/Credit"
    end

    test "updates date range", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      view
      |> form("form[phx-submit='update_date_range']", %{
        "start_date" => "2023-01-01",
        "end_date" => "2023-12-31"
      })
      |> render_submit()

      assert render(view) =~
               "Showing data from January 01, 2023 to December 31, 2023"
    end

    test "updates date range without loading collapsed sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      refute render(view) =~ "Debit/Credit"

      view
      |> form("form[phx-submit='update_date_range']", %{
        "start_date" => "2023-01-01",
        "end_date" => "2023-12-31"
      })
      |> render_submit()

      assert render(view) =~
               "Showing data from January 01, 2023 to December 31, 2023"

      refute render(view) =~ "Debit/Credit"
    end
  end

  # ---------------------------------------------------------------------------
  # Payout modal — open, close, reopen
  # ---------------------------------------------------------------------------
  describe "payout modal" do
    setup [:create_admin, :setup_qb_mocks]

    setup do
      Ledgers.ensure_basic_accounts()
      :ok
    end

    test "opens payout modal when navigating directly to payout URL", %{
      conn: conn
    } do
      payout = LedgersFixtures.payout_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/money/payouts/#{payout.id}")

      assert html =~ "Payout Details"
      assert html =~ payout.stripe_payout_id
    end

    test "payout modal shows payout amount and fees", %{conn: conn} do
      payout =
        LedgersFixtures.payout_fixture(
          payout_amount: Money.new(500, :USD),
          fee_total: Money.new(10, :USD)
        )

      {:ok, _view, html} = live(conn, ~p"/admin/money/payouts/#{payout.id}")

      assert html =~ "Payout Details"
      assert html =~ payout.stripe_payout_id
      assert html =~ "Bank Transfer"
    end

    test "close_payout_modal patches back to index and resets live_action", %{
      conn: conn
    } do
      payout = LedgersFixtures.payout_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/money/payouts/#{payout.id}")

      assert has_element?(view, "#payout-modal")

      view
      |> render_click("close_payout_modal", %{})

      refute has_element?(view, "#payout-modal")
    end

    # This is the key regression test: after closing the modal via the X button
    # (which sends close_payout_modal to the server), opening a different payout
    # must work correctly — the modal must reappear.
    test "can reopen a payout modal after closing", %{conn: conn} do
      payout1 = LedgersFixtures.payout_fixture()
      payout2 = LedgersFixtures.payout_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/money/payouts/#{payout1.id}")

      assert has_element?(view, "#payout-modal")
      assert render(view) =~ payout1.stripe_payout_id

      view |> render_click("close_payout_modal", %{})

      refute has_element?(view, "#payout-modal")

      {:ok, view2, _html2} = live(conn, ~p"/admin/money/payouts/#{payout2.id}")

      assert has_element?(view2, "#payout-modal")
      assert render(view2) =~ payout2.stripe_payout_id
    end

    test "redirects to index with error flash when payout id does not exist", %{
      conn: conn
    } do
      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/admin/money/payouts/00000000000000000000000000")

      assert to =~ "/admin/money"
      assert flash["error"] =~ "Payout not found"
    end

    # ---------------------------------------------------------------------------
    # Reconciliation row
    # ---------------------------------------------------------------------------
    test "summary shows mismatch row when no payments are linked", %{conn: conn} do
      payout =
        LedgersFixtures.payout_fixture(
          payout_amount: Money.new(100, :USD),
          fee_total: Money.new(10, :USD)
        )

      {:ok, _view, html} = live(conn, ~p"/admin/money/payouts/#{payout.id}")

      # With no linked payments: 0 - 0 - 10 ≠ 100 → mismatch
      assert html =~ "Mismatch"
      refute html =~ "Reconciled"
    end

    test "summary shows reconciled row when payments + fees balance the payout",
         %{conn: conn} do
      # Payout net $90, fee $10 → gross should be $100.
      payout =
        LedgersFixtures.payout_fixture(
          payout_amount: Money.new(90, :USD),
          fee_total: Money.new(10, :USD)
        )

      # Link a payment with the gross amount ($100)
      payment = LedgersFixtures.payment_fixture(amount: Money.new(100, :USD))
      {:ok, _} = Ledgers.link_payment_to_payout(payout, payment)

      {:ok, _view, html} = live(conn, ~p"/admin/money/payouts/#{payout.id}")

      # $100 (payments) - $0 (refunds) - $10 (fees) = $90 = payout.amount
      assert html =~ "Reconciled"
      refute html =~ "Mismatch"
    end

    test "retry QB sync button is visible when sync status is not synced", %{
      conn: conn
    } do
      payout = LedgersFixtures.payout_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/money/payouts/#{payout.id}")

      assert html =~ "Retry QB Sync"
    end
  end

  # ---------------------------------------------------------------------------
  # Payment modal — close resets live_action
  # ---------------------------------------------------------------------------
  describe "payment modal" do
    setup [:create_admin]

    setup do
      Ledgers.ensure_basic_accounts()
      :ok
    end

    test "opens payment modal when navigating to payment URL", %{conn: conn} do
      payment = LedgersFixtures.payment_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/money/payments/#{payment.id}")

      assert html =~ "Payment Details"
    end

    test "close_payment_modal patches back to index", %{conn: conn} do
      payment = LedgersFixtures.payment_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/money/payments/#{payment.id}")

      assert has_element?(view, "#payment-modal")

      view |> render_click("close_payment_modal", %{})

      refute has_element?(view, "#payment-modal")
    end

    test "can reopen a payment modal after closing", %{conn: conn} do
      payment1 = LedgersFixtures.payment_fixture()
      payment2 = LedgersFixtures.payment_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/money/payments/#{payment1.id}")

      assert has_element?(view, "#payment-modal")

      view |> render_click("close_payment_modal", %{})

      refute has_element?(view, "#payment-modal")

      {:ok, view2, _html2} =
        live(conn, ~p"/admin/money/payments/#{payment2.id}")

      assert has_element?(view2, "#payment-modal")
    end
  end

  # ---------------------------------------------------------------------------
  # Refund modal — close resets live_action
  # ---------------------------------------------------------------------------
  describe "refund modal" do
    setup [:create_admin]

    setup do
      Ledgers.ensure_basic_accounts()
      :ok
    end

    test "opens refund modal when navigating to refund URL", %{conn: conn} do
      payment = LedgersFixtures.payment_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/admin/money/payments/#{payment.id}/refund")

      assert html =~ "Process Refund"
    end

    test "close_refund_modal patches back to index", %{conn: conn} do
      payment = LedgersFixtures.payment_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/admin/money/payments/#{payment.id}/refund")

      assert has_element?(view, "#refund-modal")

      view |> render_click("close_refund_modal", %{})

      refute has_element?(view, "#refund-modal")
    end

    test "can reopen a refund modal after closing the previous one", %{
      conn: conn
    } do
      payment1 = LedgersFixtures.payment_fixture()
      payment2 = LedgersFixtures.payment_fixture()

      {:ok, view, _html} =
        live(conn, ~p"/admin/money/payments/#{payment1.id}/refund")

      assert has_element?(view, "#refund-modal")

      view |> render_click("close_refund_modal", %{})

      refute has_element?(view, "#refund-modal")

      {:ok, view2, _html2} =
        live(conn, ~p"/admin/money/payments/#{payment2.id}/refund")

      assert has_element?(view2, "#refund-modal")
    end

    test "full refund with release availability cancels completed ticket order",
         %{
           conn: conn
         } do
      %{payment: payment, ticket_order: ticket_order} =
        completed_ticket_order_with_payment!()

      refund_amount =
        payment.amount
        |> Money.to_decimal()
        |> Decimal.to_string(:normal)

      {:ok, view, _html} =
        live(conn, ~p"/admin/money/payments/#{payment.id}/refund")

      assert has_element?(view, "#refund-form")

      view
      |> form("#refund-form", %{
        "refund" => %{
          "amount" => refund_amount,
          "reason" => "Customer request",
          "release_availability" => "true"
        }
      })
      |> render_submit()

      updated_order = Repo.get!(TicketOrder, ticket_order.id)
      assert updated_order.status == :cancelled

      tickets =
        Repo.all(
          from(t in Ysc.Events.Ticket,
            where: t.ticket_order_id == ^ticket_order.id
          )
        )

      assert Enum.all?(tickets, &(&1.status == :cancelled))
    end
  end
end
