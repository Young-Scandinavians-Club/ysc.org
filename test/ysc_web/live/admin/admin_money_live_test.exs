defmodule YscWeb.AdminMoneyLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Mox
  import Ecto.Query

  alias Ysc.Ledgers
  alias Ysc.Ledgers.Refund
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

  defp completed_ticket_order_with_payment!(opts \\ []) do
    quantity = Keyword.get(opts, :quantity, 1)
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
      Tickets.create_ticket_order(user.id, event.id, %{tier.id => quantity})

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

    tickets =
      from(t in Ysc.Events.Ticket,
        where: t.ticket_order_id == ^order.id,
        order_by: t.id
      )
      |> Repo.all()

    %{payment: payment, ticket_order: completed, tickets: tickets}
  end

  defp refunds_for_payment(payment_id) do
    from(r in Refund, where: r.payment_id == ^payment_id) |> Repo.all()
  end

  defp expected_stripe_refund_id(payment, amount) do
    amount_cents = Ysc.MoneyHelper.money_to_cents(amount)

    key =
      Ysc.Stripe.Idempotency.key("admin_refund_#{payment.id}_#{amount_cents}")

    "re_test_#{key}"
  end

  describe "Admin Money" do
    setup [:create_admin]

    test "renders money management overview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")
      assert has_element?(view, "#money-date-range-form")
      assert has_element?(view, "#money-tabs")
      assert has_element?(view, "#expense-reports-inbox")
      assert has_element?(view, "#expense-reports-inbox", "All caught up")
      assert has_element?(view, "#kpi-liquidity")
      assert has_element?(view, "#kpi-period-revenue")
      assert has_element?(view, "#kpi-period-expenses")
      assert has_element?(view, "#recent-payments-section")
      assert has_element?(view, "#recent-payments-section", "Recent Payments")
    end

    test "loads ledger tab on demand", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      refute has_element?(view, "#money-ledger-tab")
      refute has_element?(view, "#money-ledger-tab th", "Debit/Credit")

      {:ok, view, _html} = live(conn, ~p"/admin/money?tab=ledger")

      assert has_element?(view, "#money-ledger-tab")
      assert has_element?(view, "#account-balances-grid")
      assert has_element?(view, "#money-ledger-tab", "Ledger Entries")
      assert has_element?(view, "#money-ledger-tab th", "Debit/Credit")
    end

    test "loads webhooks tab on demand", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      refute has_element?(view, "#money-webhooks-tab")

      {:ok, view, _html} = live(conn, ~p"/admin/money?tab=webhooks")

      assert has_element?(view, "#money-webhooks-tab")
      assert has_element?(view, "#money-webhooks-tab", "Stripe Webhook Events")
    end

    test "loads expenses tab with all expense reports", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      refute has_element?(view, "#money-expenses-tab")
      assert has_element?(view, "#expense-inbox-view-all")

      view
      |> element("#expense-inbox-view-all")
      |> render_click()

      year = DateTime.now!("America/Los_Angeles").year
      # Match URI.encode_query key order used by money_index_path/2
      expected =
        "/admin/money?end_date=#{year}-12-31&start_date=#{year}-01-01&tab=expenses"

      assert_patch(view, expected)

      assert has_element?(view, "#money-expenses-tab")
      assert has_element?(view, "#money-expenses-tab", "Expense Reports")

      assert has_element?(
               view,
               "#money-expenses-tab",
               "All reports in the selected date range"
             )
    end

    test "switching tabs does not drift the date range", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/admin/money?tab=overview&start_date=2026-01-01&end_date=2026-12-31"
        )

      assert has_element?(view, "#start_date[value='2026-01-01']")
      assert has_element?(view, "#end_date[value='2026-12-31']")

      view
      |> element("#money-tabs a", "Ledger")
      |> render_click()

      assert_patch(
        view,
        ~p"/admin/money?end_date=2026-12-31&start_date=2026-01-01&tab=ledger"
      )

      assert has_element?(view, "#start_date[value='2026-01-01']")
      assert has_element?(view, "#end_date[value='2026-12-31']")

      view
      |> element("#money-tabs a", "Overview")
      |> render_click()

      assert_patch(
        view,
        ~p"/admin/money?end_date=2026-12-31&start_date=2026-01-01&tab=overview"
      )

      assert has_element?(view, "#start_date[value='2026-01-01']")
      assert has_element?(view, "#end_date[value='2026-12-31']")
    end

    test "updates date range via URL patch", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      view
      |> form("#money-date-range-form", %{
        "date_range" => %{
          "start_date" => "2023-01-01",
          "end_date" => "2023-12-31"
        }
      })
      |> render_submit()

      assert_patch(
        view,
        ~p"/admin/money?end_date=2023-12-31&start_date=2023-01-01&tab=overview"
      )

      assert render(view) =~
               "Showing data from January 01, 2023 to December 31, 2023"
    end

    test "updates date range without loading ledger tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/money")

      refute has_element?(view, "#money-ledger-tab")

      view
      |> form("#money-date-range-form", %{
        "date_range" => %{
          "start_date" => "2023-01-01",
          "end_date" => "2023-12-31"
        }
      })
      |> render_submit()

      assert render(view) =~
               "Showing data from January 01, 2023 to December 31, 2023"

      refute has_element?(view, "#money-ledger-tab")
      refute has_element?(view, "#money-ledger-tab th", "Debit/Credit")
    end

    test "payment rows use action dropdowns instead of primary buttons", %{
      conn: conn
    } do
      Ledgers.ensure_basic_accounts()
      payment = LedgersFixtures.payment_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/money")

      assert has_element?(view, "#payment-actions-#{payment.id}")
      assert has_element?(view, "#payment-view-#{payment.id}", "View")
      assert has_element?(view, "#payment-refund-#{payment.id}", "Refund")
      refute has_element?(view, "button.bg-red-600", "Refund")
      refute has_element?(view, "button.bg-blue-600", "View")
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
      {:ok, view, _html} =
        live(conn, ~p"/admin/money/payouts/00000000000000000000000000")

      html = render(view)

      refute has_element?(view, "#payout-modal")
      assert html =~ "Payout not found"
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

    test "full refund records the Stripe refund id instead of a fabricated ledger id",
         %{conn: conn} do
      %{payment: payment} = completed_ticket_order_with_payment!()

      refund_amount =
        payment.amount
        |> Money.to_decimal()
        |> Decimal.to_string(:normal)

      {:ok, view, _html} =
        live(conn, ~p"/admin/money/payments/#{payment.id}/refund")

      view
      |> form("#refund-form", %{
        "refund" => %{
          "amount" => refund_amount,
          "reason" => "Customer request",
          "release_availability" => "false"
        }
      })
      |> render_submit()

      [refund] = refunds_for_payment(payment.id)
      expected_id = expected_stripe_refund_id(payment, payment.amount)

      assert refund.external_refund_id == expected_id
      assert String.starts_with?(refund.external_refund_id, "re_test_")

      refute refund.external_refund_id =~
               ~r/^admin_refund_[0-9A-HJKMNP-TV-Z]{26}$/

      updated_payment = Ledgers.get_payment(payment.id)
      assert updated_payment.status == :refunded
    end

    test "does not record a ledger refund or cancel tickets when Stripe fails",
         %{conn: conn} do
      previous = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, Ysc.StripeRetrieveFailClient)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, previous)
      end)

      %{payment: payment, ticket_order: ticket_order} =
        completed_ticket_order_with_payment!()

      refund_amount =
        payment.amount
        |> Money.to_decimal()
        |> Decimal.to_string(:normal)

      {:ok, view, _html} =
        live(conn, ~p"/admin/money/payments/#{payment.id}/refund")

      html =
        view
        |> form("#refund-form", %{
          "refund" => %{
            "amount" => refund_amount,
            "reason" => "Customer request",
            "release_availability" => "true"
          }
        })
        |> render_submit()

      assert html =~ "Stripe declined the refund"
      assert refunds_for_payment(payment.id) == []
      assert Ledgers.get_payment(payment.id).status == :completed
      assert Repo.get!(TicketOrder, ticket_order.id).status == :completed

      tickets =
        Repo.all(
          from(t in Ysc.Events.Ticket,
            where: t.ticket_order_id == ^ticket_order.id
          )
        )

      assert Enum.all?(tickets, &(&1.status == :confirmed))
    end

    test "rejects refunds when the payment has no Stripe payment intent", %{
      conn: conn
    } do
      %{payment: payment, ticket_order: ticket_order} =
        completed_ticket_order_with_payment!()

      {:ok, payment} =
        payment
        |> Ecto.Changeset.change(%{external_payment_id: nil})
        |> Repo.update()

      refund_amount =
        payment.amount
        |> Money.to_decimal()
        |> Decimal.to_string(:normal)

      {:ok, view, _html} =
        live(conn, ~p"/admin/money/payments/#{payment.id}/refund")

      html =
        view
        |> form("#refund-form", %{
          "refund" => %{
            "amount" => refund_amount,
            "reason" => "Customer request",
            "release_availability" => "true"
          }
        })
        |> render_submit()

      assert html =~ "no Stripe payment found"
      assert refunds_for_payment(payment.id) == []
      assert Ledgers.get_payment(payment.id).status == :completed
      assert Repo.get!(TicketOrder, ticket_order.id).status == :completed
    end

    test "partial ticket refund issues Stripe first then cancels only selected tickets",
         %{conn: conn} do
      %{payment: payment, ticket_order: ticket_order, tickets: tickets} =
        completed_ticket_order_with_payment!(quantity: 2)

      [first | [second]] = tickets

      {:ok, view, _html} =
        live(conn, ~p"/admin/money/payments/#{payment.id}/refund")

      html =
        view
        |> form("#refund-form", %{
          "refund" => %{
            "ticket_ids" => [first.id],
            "reason" => "One ticket unused"
          }
        })
        |> render_submit()

      assert html =~ "Refunded 1 ticket(s) successfully"

      [refund] = refunds_for_payment(payment.id)
      expected_amount = Money.new(50, :USD)

      assert refund.external_refund_id ==
               expected_stripe_refund_id(payment, expected_amount)

      assert Money.equal?(refund.amount, expected_amount)
      assert Repo.get!(Ysc.Events.Ticket, first.id).status == :cancelled
      assert Repo.get!(Ysc.Events.Ticket, second.id).status == :confirmed
      assert Repo.get!(TicketOrder, ticket_order.id).status == :completed
      assert Ledgers.get_payment(payment.id).status == :completed
    end
  end
end
