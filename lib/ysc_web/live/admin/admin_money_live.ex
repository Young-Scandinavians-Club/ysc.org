defmodule YscWeb.AdminMoneyLive do
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.CoreComponents

  alias Ysc.Ledgers
  alias Ysc.Accounts
  alias Ysc.Webhooks
  alias Ysc.Bookings
  alias Ysc.Bookings.BookingLocker
  alias Ysc.MoneyHelper
  alias Ysc.Tickets
  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Repo
  alias YscWeb.AdminBadgeHelpers
  alias YscWeb.DateDisplay
  import Ecto.Query

  require Ysc.Logging

  @liquidity_account_names ["cash", "stripe_account"]
  @expense_account_names ["stripe_fees", "discount_expense"]

  @impl true
  def mount(_params, _session, socket) do
    # Get timezone from connect params (browser sends via LiveSocket)
    connect_params = get_connect_params(socket) || %{}
    timezone = Map.get(connect_params, "timezone", "America/Los_Angeles")

    # Set default date range to current calendar year
    current_year = DateTime.now!("America/Los_Angeles").year
    start_date = DateTime.new!(Date.new!(current_year, 1, 1), ~T[00:00:00])
    end_date = DateTime.new!(Date.new!(current_year, 12, 31), ~T[23:59:59])

    # Initialize socket with placeholder values for fast initial render
    socket =
      socket
      |> assign(:timezone, timezone)
      |> assign(:page_title, "Money")
      |> assign(:active_page, :money)
      |> assign(:active_tab, :overview)
      |> assign(:loading_money_data, true)
      |> assign(:accounts_with_balances, [])
      |> assign(:current_accounts_with_balances, [])
      |> assign(:liquidity_total, Money.new(0, :USD))
      |> assign(:period_revenue_total, Money.new(0, :USD))
      |> assign(:period_expenses_total, Money.new(0, :USD))
      |> assign(:start_date, start_date)
      |> assign(:end_date, end_date)
      |> assign(:show_refund_modal, false)
      |> assign(:show_credit_modal, false)
      |> assign(:show_webhook_modal, false)
      |> assign(:show_payout_modal, false)
      |> assign(:selected_payment, nil)
      |> assign(:selected_user, nil)
      |> assign(:selected_webhook, nil)
      |> assign(:selected_payout, nil)
      |> assign(:ticket_order, nil)
      |> assign(:refund_form, to_form(%{}, as: :refund))
      |> assign(:credit_form, to_form(%{}, as: :credit))
      |> assign(:show_payment_modal, false)
      |> assign(:payment_refunds, [])
      |> assign(:payment_ledger_entries, [])
      |> assign(:payment_related_entity, nil)
      |> assign(:ledger_accounts, [])
      |> assign(:tabs_loaded, %{
        overview: false,
        expenses: false,
        ledger: false,
        webhooks: false
      })
      |> assign(:payments_page, 1)
      |> assign(:ledger_entries_page, 1)
      |> assign(:webhooks_page, 1)
      |> assign(:expense_reports_page, 1)
      |> assign(:per_page, 20)
      |> assign(:show_expense_report_modal, false)
      |> assign(:selected_expense_report, nil)
      |> assign(
        :expense_report_status_form,
        to_form(%{}, as: :expense_report_status)
      )
      |> assign(:payments_end?, true)
      |> assign(:payments_empty?, true)
      |> assign(:payments_count, 0)
      |> assign(:ledger_entries, [])
      |> assign(:ledger_entries_end?, true)
      |> assign(:webhook_events, [])
      |> assign(:webhooks_end?, true)
      |> assign(:expense_reports, [])
      |> assign(:expense_reports_end?, true)
      |> assign(:expense_reports_inbox, [])
      |> stream(:payments, [])
      |> assign_date_range_form()

    # Schedule data loading only when connected (stateful mount)
    if connected?(socket) do
      send(self(), :load_money_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_money_data, socket) do
    socket = assign(socket, :loading_money_data, false)

    socket =
      if socket.assigns.active_tab == :overview do
        load_overview_data(socket)
      else
        ensure_tab_loaded(socket, socket.assigns.active_tab)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    active_tab = parse_tab(Map.get(params, "tab", "overview"))

    {socket, dates_changed?} = assign_dates_from_params(socket, params)

    socket =
      socket
      |> assign(:active_tab, active_tab)
      |> assign(:live_action, socket.assigns.live_action || :index)

    socket =
      if connected?(socket) do
        socket
        |> apply_action(socket.assigns.live_action, params)
        |> maybe_refresh_for_date_change(dates_changed?)
        |> ensure_tab_loaded(active_tab)
      else
        socket
      end

    {:noreply, socket}
  end

  # Normalizes entity type strings to atoms safely
  defp normalize_entity_type("administration"), do: :administration
  defp normalize_entity_type("booking"), do: :booking
  defp normalize_entity_type("donation"), do: :donation
  defp normalize_entity_type("event"), do: :event
  defp normalize_entity_type("membership"), do: :membership
  defp normalize_entity_type(_unknown), do: :administration

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Money")
    |> assign(:show_refund_modal, false)
    |> assign(:show_payment_modal, false)
    |> assign(:show_payout_modal, false)
    |> assign(:selected_payment, nil)
    |> assign(:selected_payout, nil)
    |> assign(:payment_refunds, [])
    |> assign(:payment_ledger_entries, [])
    |> assign(:payment_related_entity, nil)
  end

  defp apply_action(socket, :view_payment, %{"id" => payment_id}) do
    payment = Ledgers.get_payment_with_associations(payment_id)

    if payment do
      # Add payment type info
      payment = Ledgers.add_payment_type_info(payment)

      # Get refunds for this payment
      refunds =
        from(r in Ysc.Ledgers.Refund,
          where: r.payment_id == ^payment_id,
          preload: [:user],
          order_by: [desc: r.inserted_at]
        )
        |> Repo.all()

      # Get ledger entries for this payment
      ledger_entries =
        from(e in Ysc.Ledgers.LedgerEntry,
          where: e.payment_id == ^payment_id,
          preload: [:account],
          order_by: [desc: e.inserted_at]
        )
        |> Repo.all()

      # Get related entity (booking or ticket order)
      related_entity = Ledgers.get_payment_related_entity(payment)

      socket
      |> assign(:page_title, "Payment Details")
      |> assign(:show_payment_modal, true)
      |> assign(:selected_payment, payment)
      |> assign(:payment_refunds, refunds)
      |> assign(:payment_ledger_entries, ledger_entries)
      |> assign(:payment_related_entity, related_entity)
    else
      socket
      |> YscWeb.Flash.put_toast(:error, "Payment not found", title: "Payment")
      |> push_patch(to: build_money_path(socket))
    end
  end

  defp apply_action(socket, :refund_payment, %{"id" => payment_id}) do
    payment = Ledgers.get_payment_with_associations(payment_id)

    if payment do
      # Check if this payment is for a ticket order
      ticket_order =
        from(e in Ysc.Ledgers.LedgerEntry,
          where: e.payment_id == ^payment_id,
          where: e.related_entity_type == :event,
          limit: 1
        )
        |> Repo.one()
        |> case do
          nil -> nil
          _entry -> Tickets.get_ticket_order_by_payment_id(payment_id)
        end

      # Initialize refund form with ticket selection fields
      refund_form =
        if ticket_order do
          {%{},
           %{
             amount: :string,
             reason: :string,
             release_availability: :boolean,
             ticket_ids: {:array, :string}
           }}
          |> Ecto.Changeset.cast(%{}, [
            :amount,
            :reason,
            :release_availability,
            :ticket_ids
          ])
          |> to_form(as: :refund)
        else
          {%{},
           %{amount: :string, reason: :string, release_availability: :boolean}}
          |> Ecto.Changeset.cast(%{}, [:amount, :reason, :release_availability])
          |> to_form(as: :refund)
        end

      socket
      |> assign(:page_title, "Refund Payment")
      |> assign(:show_refund_modal, true)
      |> assign(:selected_payment, payment)
      |> assign(:ticket_order, ticket_order)
      |> assign(:refund_form, refund_form)
    else
      socket
      |> YscWeb.Flash.put_toast(:error, "Payment not found", title: "Payment")
      |> push_patch(to: build_money_path(socket))
    end
  end

  defp apply_action(socket, :view_payout, %{"id" => payout_id}) do
    # Find payout by ID (the ID in the URL is the payout ID, not payment ID)
    payout =
      try do
        Ledgers.get_payout!(payout_id)
      rescue
        Ecto.NoResultsError -> nil
      end

    if payout do
      socket
      |> assign(:page_title, "Payout Details")
      |> assign(:show_payout_modal, true)
      |> assign(:selected_payout, payout)
    else
      socket
      |> YscWeb.Flash.put_toast(:error, "Payout not found", title: "Payout")
      |> push_patch(to: build_money_path(socket))
    end
  end

  defp apply_action(socket, _action, _params) do
    socket
  end

  # Helper to build money path with tab and date range preserved
  defp build_money_path(socket, sub_path \\ "") do
    base_path = ~p"/admin/money"

    full_path =
      if sub_path != "", do: "#{base_path}#{sub_path}", else: base_path

    query_params = money_query_params(socket)

    if map_size(query_params) > 0 do
      "#{full_path}?#{URI.encode_query(query_params)}"
    else
      full_path
    end
  end

  defp money_query_params(socket_or_assigns, overrides \\ %{})

  defp money_query_params(%Phoenix.LiveView.Socket{} = socket, overrides) do
    money_query_params(socket.assigns, overrides)
  end

  defp money_query_params(assigns, overrides) when is_map(assigns) do
    base = %{
      "tab" => to_string(assigns[:active_tab] || :overview)
    }

    base =
      if assigns[:start_date] && assigns[:end_date] do
        Map.merge(base, %{
          # Use calendar dates as stored — do not shift into the browser TZ.
          # Shifting UTC midnight into America/Los_Angeles turns Jan 1 into Dec 31
          # and drifts the range by one day on every tab patch.
          "start_date" => format_date_param(assigns[:start_date]),
          "end_date" => format_date_param(assigns[:end_date])
        })
      else
        base
      end

    Map.merge(base, stringify_query_overrides(overrides))
  end

  defp stringify_query_overrides(overrides) do
    Map.new(overrides, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp money_index_path(socket_or_assigns, overrides) do
    ~p"/admin/money?#{money_query_params(socket_or_assigns, overrides)}"
  end

  defp parse_tab("expenses"), do: :expenses
  defp parse_tab("ledger"), do: :ledger
  defp parse_tab("webhooks"), do: :webhooks
  defp parse_tab(_), do: :overview

  defp assign_dates_from_params(socket, params) do
    with start_str when is_binary(start_str) and start_str != "" <-
           params["start_date"],
         end_str when is_binary(end_str) and end_str != "" <- params["end_date"],
         {:ok, start_date} <- parse_date_to_datetime(start_str, ~T[00:00:00]),
         {:ok, end_date} <- parse_date_to_datetime(end_str, ~T[23:59:59]) do
      dates_changed? =
        socket.assigns.start_date != start_date or
          socket.assigns.end_date != end_date

      {
        socket
        |> assign(:start_date, start_date)
        |> assign(:end_date, end_date)
        |> assign_date_range_form(),
        dates_changed?
      }
    else
      _ -> {socket, false}
    end
  end

  defp assign_date_range_form(socket) do
    assign(
      socket,
      :date_range_form,
      to_form(
        %{
          "start_date" => format_date_param(socket.assigns.start_date),
          "end_date" => format_date_param(socket.assigns.end_date)
        },
        as: :date_range
      )
    )
  end

  defp maybe_refresh_for_date_change(socket, false), do: socket

  defp maybe_refresh_for_date_change(socket, true) do
    any_loaded? =
      socket.assigns.tabs_loaded.overview or
        socket.assigns.tabs_loaded.expenses or
        socket.assigns.tabs_loaded.ledger or
        socket.assigns.tabs_loaded.webhooks

    if any_loaded? do
      socket
      |> assign(:payments_page, 1)
      |> assign(:ledger_entries_page, 1)
      |> assign(:webhooks_page, 1)
      |> assign(:expense_reports_page, 1)
      |> refresh_loaded_tab_data()
    else
      socket
    end
  end

  defp refresh_loaded_tab_data(socket) do
    tabs_loaded = socket.assigns.tabs_loaded

    socket =
      if tabs_loaded.overview do
        load_overview_data(socket)
      else
        socket
      end

    socket =
      if tabs_loaded.expenses do
        paginate_expense_reports(socket, 1)
      else
        socket
      end

    socket =
      if tabs_loaded.ledger do
        socket
        |> load_period_accounts()
        |> paginate_ledger_entries(1)
      else
        socket
      end

    if tabs_loaded.webhooks do
      paginate_webhooks(socket, 1)
    else
      socket
    end
  end

  defp ensure_tab_loaded(socket, :overview) do
    cond do
      socket.assigns.tabs_loaded.overview ->
        # Re-stream the current page so rows survive Overview remount after tab switches
        paginate_payments(socket, socket.assigns.payments_page)

      socket.assigns.loading_money_data ->
        # Wait for :load_money_data so the loading skeleton clears once
        socket

      true ->
        load_overview_data(socket)
    end
  end

  defp ensure_tab_loaded(socket, :expenses) do
    if socket.assigns.tabs_loaded.expenses do
      socket
    else
      socket
      |> paginate_expense_reports(1)
      |> assign(
        :tabs_loaded,
        Map.put(socket.assigns.tabs_loaded, :expenses, true)
      )
    end
  end

  defp ensure_tab_loaded(socket, :ledger) do
    if socket.assigns.tabs_loaded.ledger do
      socket
    else
      socket
      |> load_period_accounts()
      |> paginate_ledger_entries(1)
      |> assign(
        :tabs_loaded,
        Map.put(socket.assigns.tabs_loaded, :ledger, true)
      )
    end
  end

  defp ensure_tab_loaded(socket, :webhooks) do
    if socket.assigns.tabs_loaded.webhooks do
      socket
    else
      socket
      |> paginate_webhooks(1)
      |> assign(
        :tabs_loaded,
        Map.put(socket.assigns.tabs_loaded, :webhooks, true)
      )
    end
  end

  defp load_overview_data(socket) do
    start_date = socket.assigns.start_date
    end_date = socket.assigns.end_date

    {period_accounts, current_accounts, ledger_accounts} =
      Ledgers.get_overview_accounts_with_balances(start_date, end_date)

    socket
    |> assign(:accounts_with_balances, period_accounts)
    |> assign(:current_accounts_with_balances, current_accounts)
    |> assign(:ledger_accounts, ledger_accounts)
    |> assign(
      :liquidity_total,
      sum_account_balances(current_accounts, @liquidity_account_names)
    )
    |> assign(
      :period_revenue_total,
      sum_balances_by_account_type(period_accounts, "revenue")
    )
    |> assign(
      :period_expenses_total,
      sum_account_balances(period_accounts, @expense_account_names)
    )
    |> load_expense_reports_inbox()
    |> paginate_payments(1)
    |> assign(
      :tabs_loaded,
      Map.put(socket.assigns.tabs_loaded, :overview, true)
    )
  end

  defp load_period_accounts(socket) do
    accounts_with_balances =
      Ledgers.get_accounts_with_balances(
        socket.assigns.start_date,
        socket.assigns.end_date
      )

    assign(socket, :accounts_with_balances, accounts_with_balances)
  end

  defp load_expense_reports_inbox(socket) do
    expense_reports =
      from(er in ExpenseReport,
        where: er.status == "submitted",
        preload: [:user],
        order_by: [asc: er.inserted_at],
        limit: 50
      )
      |> Repo.all()

    assign(socket, :expense_reports_inbox, expense_reports)
  end

  defp sum_account_balances(accounts_with_balances, account_names) do
    accounts_with_balances
    |> Enum.filter(fn %{account: account} -> account.name in account_names end)
    |> sum_balances()
  end

  defp sum_balances_by_account_type(accounts_with_balances, account_type) do
    accounts_with_balances
    |> Enum.filter(fn %{account: account} ->
      to_string(account.account_type) == account_type
    end)
    |> sum_balances()
  end

  defp sum_balances(account_data_list) do
    Enum.reduce(account_data_list, Money.new(0, :USD), fn %{balance: balance},
                                                          acc ->
      case Money.add(acc, balance || Money.new(0, :USD)) do
        {:ok, result} -> result
        {:error, _reason} -> acc
      end
    end)
  end

  @impl true
  def handle_event("show_refund_modal", %{"payment_id" => payment_id}, socket) do
    path = build_money_path(socket, "/payments/#{payment_id}/refund")
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("show_credit_modal", %{"user_id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)

    {:noreply,
     socket
     |> assign(:show_credit_modal, true)
     |> assign(:selected_user, user)
     |> assign(:credit_form, to_form(%{}, as: :credit))}
  end

  @impl true
  def handle_event("close_refund_modal", _params, socket) do
    {:noreply, push_patch(socket, to: build_money_path(socket))}
  end

  @impl true
  def handle_event("close_credit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_credit_modal, false)
     |> assign(:selected_user, nil)}
  end

  @impl true
  def handle_event("show_webhook_modal", %{"webhook_id" => webhook_id}, socket) do
    webhook = Webhooks.get_webhook_event(webhook_id)

    {:noreply,
     socket
     |> assign(:show_webhook_modal, true)
     |> assign(:selected_webhook, webhook)}
  end

  @impl true
  def handle_event("close_webhook_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_webhook_modal, false)
     |> assign(:selected_webhook, nil)}
  end

  @impl true
  def handle_event("show_payout_modal", %{"payment_id" => payment_id}, socket) do
    # Find the payout associated with this payment
    # When payment_type_info.type == "Payout", the payment IS the payout payment
    payout =
      from(p in Ysc.Ledgers.Payout,
        where: p.payment_id == ^payment_id,
        limit: 1
      )
      |> Repo.one()

    if payout do
      path = build_money_path(socket, "/payouts/#{payout.id}")
      {:noreply, push_patch(socket, to: path)}
    else
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(:error, "Payout not found for this payment",
         title: "Payout"
       )}
    end
  end

  @impl true
  def handle_event("close_payout_modal", _params, socket) do
    {:noreply, push_patch(socket, to: build_money_path(socket))}
  end

  @impl true
  def handle_event("retry_payout_qb_sync", %{"payout_id" => payout_id}, socket) do
    payout = Repo.get!(Ysc.Ledgers.Payout, payout_id)

    {:ok, payout} =
      payout
      |> Ysc.Ledgers.Payout.changeset(%{
        quickbooks_sync_status: nil,
        quickbooks_sync_error: nil,
        quickbooks_last_sync_attempt_at: nil
      })
      |> Repo.update()

    %{payout_id: to_string(payout.id)}
    |> YscWeb.Workers.QuickbooksSyncPayoutWorker.new()
    |> Oban.insert()

    payout = Repo.preload(payout, [:payments, :refunds])

    {:noreply,
     socket
     |> assign(:selected_payout, payout)
     |> YscWeb.Flash.put_toast(
       :info,
       "QuickBooks sync job enqueued for payout #{payout.stripe_payout_id}",
       title: "Payout"
     )}
  end

  @impl true
  def handle_event("show_payment_modal", %{"payment_id" => payment_id}, socket) do
    path = build_money_path(socket, "/payments/#{payment_id}")
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("close_payment_modal", _params, socket) do
    {:noreply, push_patch(socket, to: build_money_path(socket))}
  end

  @impl true
  def handle_event("process_refund", %{"refund" => refund_params}, socket) do
    %{selected_payment: payment, ticket_order: ticket_order} = socket.assigns

    # Check if this is a partial ticket refund
    ticket_ids =
      if refund_params["ticket_ids"], do: refund_params["ticket_ids"], else: []

    # If ticket IDs are provided, refund individual tickets. Compute the
    # amount without mutating anything, issue the Stripe refund, and only
    # cancel the tickets once the refund actually succeeded -- otherwise a
    # Stripe failure would leave tickets cancelled with no money refunded.
    if ticket_order && ticket_ids != [] do
      case Tickets.calculate_refund_amount(ticket_order, ticket_ids) do
        {:ok, calculated_refund_amount} ->
          case create_stripe_refund_and_record(
                 payment,
                 calculated_refund_amount,
                 refund_params["reason"]
               ) do
            {:ok, {_refund, _transaction, _entries}} ->
              case Tickets.refund_tickets(
                     ticket_order,
                     ticket_ids,
                     refund_params["reason"]
                   ) do
                {:ok, _refund_info} ->
                  # Refresh data
                  %{start_date: start_date, end_date: end_date} = socket.assigns

                  accounts_with_balances =
                    Ledgers.get_accounts_with_balances(start_date, end_date)

                  # Navigate to payment details view to show the refund
                  payment_path =
                    build_money_path(socket, "/payments/#{payment.id}")

                  {:noreply,
                   socket
                   |> YscWeb.Flash.put_toast(
                     :info,
                     "Refunded #{length(ticket_ids)} ticket(s) successfully. Amount: #{Money.to_string!(calculated_refund_amount)}",
                     title: "Refund"
                   )
                   |> assign(:accounts_with_balances, accounts_with_balances)
                   |> assign(:payments_page, 1)
                   |> assign(:ledger_entries_page, 1)
                   |> assign(:webhooks_page, 1)
                   |> paginate_payments(1)
                   |> paginate_ledger_entries(1)
                   |> paginate_webhooks(1)
                   |> push_patch(to: payment_path)}

                {:error, reason} ->
                  Ysc.Logging.error(
                    "Ticket refund issued in Stripe but tickets failed to cancel",
                    payment_id: payment.id,
                    ticket_order_id: ticket_order.id,
                    ticket_ids: ticket_ids,
                    error: inspect(reason)
                  )

                  {:noreply,
                   socket
                   |> YscWeb.Flash.put_toast(
                     :error,
                     "Refund was processed in Stripe, but the tickets could not be marked cancelled. Please cancel them manually.",
                     title: "Refund"
                   )}
              end

            {:error, {:stripe_error, _msg}} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(
                 :error,
                 "Stripe declined the refund. Check the payment in the Stripe dashboard, or contact engineering if this persists.",
                 title: "Refund"
               )}

            {:error, :no_stripe_payment} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(
                 :error,
                 "Cannot process refund: no Stripe payment found for this payment.",
                 title: "Refund"
               )}

            {:error, _changeset} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(
                 :error,
                 "Failed to process refund in ledger",
                 title: "Refund"
               )}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :error,
             "Failed to refund tickets: #{inspect(reason)}",
             title: "Refund"
           )}
      end
    else
      # Full refund (existing logic)
      case parse_amount_string(refund_params["amount"]) do
        {:ok, refund_amount} ->
          # Check if we should release availability
          release_availability = refund_params["release_availability"] == "true"

          case create_stripe_refund_and_record(
                 payment,
                 refund_amount,
                 refund_params["reason"]
               ) do
            {:ok, {_refund, _transaction, _entries}} ->
              # If checkbox is checked, cancel booking or ticket order to release availability
              release_result =
                if release_availability do
                  release_availability_for_payment(payment.id)
                else
                  :ok
                end

              # Refresh data with current date range
              %{start_date: start_date, end_date: end_date} = socket.assigns

              accounts_with_balances =
                Ledgers.get_accounts_with_balances(start_date, end_date)

              flash_message =
                case release_result do
                  {:ok, :booking_refunded} ->
                    "Refund processed successfully and booking marked as refunded (dates released)"

                  {:ok, :ticket_order_canceled} ->
                    "Refund processed successfully and tickets released"

                  {:ok, :not_found} ->
                    "Refund processed successfully (no booking or ticket order found to release)"

                  {:error, reason} ->
                    Ysc.Logging.warning(
                      "Refund processed but failed to release availability",
                      payment_id: payment.id,
                      reason: reason
                    )

                    "Refund processed successfully (warning: failed to release availability)"

                  _ ->
                    "Refund processed successfully"
                end

              # Navigate to payment details view to show the refund
              payment_path = build_money_path(socket, "/payments/#{payment.id}")

              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(:info, flash_message, title: "Refund")
               |> assign(:accounts_with_balances, accounts_with_balances)
               |> assign(:payments_page, 1)
               |> assign(:ledger_entries_page, 1)
               |> assign(:webhooks_page, 1)
               |> paginate_payments(1)
               |> paginate_ledger_entries(1)
               |> paginate_webhooks(1)
               |> push_patch(to: payment_path)}

            {:error, {:stripe_error, _msg}} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(
                 :error,
                 "Stripe declined the refund. Check the payment in the Stripe dashboard, or contact engineering if this persists.",
                 title: "Refund"
               )}

            {:error, :no_stripe_payment} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(
                 :error,
                 "Cannot process refund: no Stripe payment found for this payment.",
                 title: "Refund"
               )}

            {:error, _changeset} ->
              {:noreply,
               socket
               |> YscWeb.Flash.put_toast(:error, "Failed to process refund",
                 title: "Refund"
               )}
          end

        {:error, _} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:error, "Invalid amount format",
             title: "Refund"
           )}
      end
    end
  end

  @impl true
  def handle_event("process_credit", %{"credit" => credit_params}, socket) do
    %{selected_user: user} = socket.assigns

    case parse_amount_string(credit_params["amount"]) do
      {:ok, amount} ->
        credit_attrs = %{
          user_id: user.id,
          amount: amount,
          reason: credit_params["reason"],
          entity_type:
            normalize_entity_type(
              credit_params["entity_type"] || "administration"
            ),
          entity_id: credit_params["entity_id"]
        }

        case Ledgers.add_credit(credit_attrs) do
          {:ok, _payment, _transaction, _entries} ->
            # Refresh data with current date range
            %{start_date: start_date, end_date: end_date} = socket.assigns

            accounts_with_balances =
              Ledgers.get_accounts_with_balances(start_date, end_date)

            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(:info, "Credit added successfully",
               title: "Credit"
             )
             |> assign(:show_credit_modal, false)
             |> assign(:selected_user, nil)
             |> assign(:accounts_with_balances, accounts_with_balances)
             |> assign(:payments_page, 1)
             |> assign(:ledger_entries_page, 1)
             |> assign(:webhooks_page, 1)
             |> paginate_payments(1)
             |> paginate_ledger_entries(1)
             |> paginate_webhooks(1)}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(:error, "Failed to add credit",
               title: "Credit"
             )}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:error, "Invalid amount format",
           title: "Credit"
         )}
    end
  end

  @impl true
  def handle_event("validate_refund", %{"refund" => refund_params}, socket) do
    %{ticket_order: ticket_order} = socket.assigns

    # For ticket orders, ensure ticket_ids are always present in refund_params
    # When checkboxes are clicked, only checked ones are sent in the form params
    # So we use the params directly (they contain all currently checked boxes)
    refund_params =
      if ticket_order do
        # Use ticket_ids from params if present, otherwise use empty list
        ticket_ids = refund_params["ticket_ids"] || []
        Map.put(refund_params, "ticket_ids", ticket_ids)
      else
        refund_params
      end

    # If this is a ticket order and tickets are selected, calculate the refund amount
    refund_params =
      if ticket_order && refund_params["ticket_ids"] &&
           refund_params["ticket_ids"] != [] do
        # Convert ticket_ids from strings to proper format for comparison
        ticket_ids = refund_params["ticket_ids"]

        # Calculate refund amount based on selected tickets
        refund_amount =
          ticket_order.tickets
          |> Enum.filter(fn ticket ->
            to_string(ticket.id) in ticket_ids &&
              ticket.status in [:confirmed, :pending]
          end)
          |> Enum.reduce(Money.new(0, :USD), fn ticket, acc ->
            case ticket.ticket_tier.type do
              :free ->
                acc

              :donation ->
                # For donation tickets, calculate proportionally
                if ticket_order.total_amount do
                  donation_tickets_count =
                    ticket_order.tickets
                    |> Enum.filter(fn t ->
                      t.ticket_tier.type == :donation &&
                        t.status in [:confirmed, :pending]
                    end)
                    |> length()

                  if donation_tickets_count > 0 do
                    {:ok, ticket_amount} =
                      Money.div(
                        ticket_order.total_amount,
                        donation_tickets_count
                      )

                    case Money.add(acc, ticket_amount) do
                      {:ok, new_total} -> new_total
                      {:error, _} -> acc
                    end
                  else
                    acc
                  end
                else
                  acc
                end

              _ ->
                # For paid tickets, use the tier price
                if ticket.ticket_tier.price do
                  case Money.add(acc, ticket.ticket_tier.price) do
                    {:ok, new_total} -> new_total
                    {:error, _} -> acc
                  end
                else
                  acc
                end
            end
          end)

        # Update the amount in refund_params with the calculated value
        Map.put(refund_params, "amount", Money.to_string!(refund_amount))
      else
        # If no tickets selected and this is a ticket order, clear the amount
        if ticket_order do
          Map.put(refund_params, "amount", "")
        else
          refund_params
        end
      end

    changeset =
      %{}
      |> refund_changeset(refund_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :refund_form, to_form(changeset, as: :refund))}
  end

  @impl true
  def handle_event("validate_credit", %{"credit" => credit_params}, socket) do
    changeset =
      %{}
      |> credit_changeset(credit_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :credit_form, to_form(changeset, as: :credit))}
  end

  @impl true
  def handle_event("payments_next-page", _, socket) do
    {:noreply, paginate_payments(socket, socket.assigns.payments_page + 1)}
  end

  @impl true
  def handle_event("payments_prev-page", _, socket) do
    if socket.assigns.payments_page > 1 do
      {:noreply, paginate_payments(socket, socket.assigns.payments_page - 1)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("ledger_entries_next-page", _, socket) do
    {:noreply,
     paginate_ledger_entries(socket, socket.assigns.ledger_entries_page + 1)}
  end

  @impl true
  def handle_event("ledger_entries_prev-page", _, socket) do
    if socket.assigns.ledger_entries_page > 1 do
      {:noreply,
       paginate_ledger_entries(socket, socket.assigns.ledger_entries_page - 1)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("webhooks_next-page", _, socket) do
    {:noreply, paginate_webhooks(socket, socket.assigns.webhooks_page + 1)}
  end

  @impl true
  def handle_event("webhooks_prev-page", _, socket) do
    if socket.assigns.webhooks_page > 1 do
      {:noreply, paginate_webhooks(socket, socket.assigns.webhooks_page - 1)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("expense_reports_next-page", _, socket) do
    {:noreply,
     paginate_expense_reports(socket, socket.assigns.expense_reports_page + 1)}
  end

  @impl true
  def handle_event("expense_reports_prev-page", _, socket) do
    if socket.assigns.expense_reports_page > 1 do
      {:noreply,
       paginate_expense_reports(socket, socket.assigns.expense_reports_page - 1)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "show_expense_report_status_modal",
        %{"expense_report_id" => expense_report_id},
        socket
      ) do
    expense_report =
      from(er in ExpenseReport,
        where: er.id == ^expense_report_id,
        preload: [
          :user,
          :expense_items,
          :income_items,
          :address,
          :bank_account,
          :event
        ]
      )
      |> Repo.one()

    if expense_report do
      status_form =
        %{status: expense_report.status}
        |> expense_report_status_changeset()
        |> to_form(as: :expense_report_status)

      {:noreply,
       socket
       |> assign(:show_expense_report_modal, true)
       |> assign(:selected_expense_report, expense_report)
       |> assign(:expense_report_status_form, status_form)}
    else
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(:error, "Expense report not found",
         title: "Expense report"
       )}
    end
  end

  @impl true
  def handle_event("close_expense_report_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_expense_report_modal, false)
     |> assign(:selected_expense_report, nil)
     |> assign(
       :expense_report_status_form,
       to_form(%{}, as: :expense_report_status)
     )}
  end

  @impl true
  def handle_event(
        "update_expense_report_status",
        %{"expense_report_status" => status_params},
        socket
      ) do
    %{selected_expense_report: expense_report} = socket.assigns

    # Reload expense report with all required associations before updating
    expense_report =
      from(er in ExpenseReport,
        where: er.id == ^expense_report.id,
        preload: [
          :user,
          :expense_items,
          :income_items,
          :address,
          :bank_account,
          :event
        ]
      )
      |> Repo.one()

    if expense_report do
      case ExpenseReports.update_expense_report(expense_report, status_params) do
        {:ok, _updated_report} ->
          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(
             :info,
             "Expense report status updated successfully",
             title: "Expense report"
           )
           |> assign(:show_expense_report_modal, false)
           |> assign(:selected_expense_report, nil)
           |> load_expense_reports_inbox()
           |> maybe_refresh_expense_reports_list()
           |> assign(
             :expense_report_status_form,
             to_form(%{}, as: :expense_report_status)
           )}

        {:error, changeset} ->
          error_message =
            case changeset.errors do
              [] -> "Failed to update expense report status"
              errors -> "Validation errors: #{inspect(errors)}"
            end

          {:noreply,
           socket
           |> YscWeb.Flash.put_toast(:error, error_message,
             title: "Expense report"
           )
           |> assign(
             :expense_report_status_form,
             to_form(changeset, as: :expense_report_status)
           )}
      end
    else
      {:noreply,
       socket
       |> YscWeb.Flash.put_toast(:error, "Expense report not found",
         title: "Expense report"
       )
       |> assign(:show_expense_report_modal, false)
       |> assign(:selected_expense_report, nil)}
    end
  end

  @impl true
  def handle_event(
        "update_date_range",
        %{
          "date_range" => %{
            "start_date" => start_date_str,
            "end_date" => end_date_str
          }
        },
        socket
      ) do
    path =
      money_index_path(socket, %{
        "tab" => to_string(socket.assigns.active_tab),
        "start_date" => start_date_str,
        "end_date" => end_date_str
      })

    {:noreply, push_patch(socket, to: path)}
  end

  # Pagination helpers
  defp paginate_payments(socket, page) when page >= 1 do
    %{per_page: per_page, start_date: start_date, end_date: end_date} =
      socket.assigns

    offset = (page - 1) * per_page

    recent_payments =
      from(p in Ysc.Ledgers.Payment,
        preload: [:user, :payment_method],
        where: p.payment_date >= ^start_date,
        where: p.payment_date <= ^end_date,
        order_by: [desc: p.payment_date],
        limit: ^per_page,
        offset: ^offset
      )
      |> Repo.all()
      |> Ledgers.add_payment_type_info_batch()

    socket
    |> stream(:payments, recent_payments, reset: true)
    |> assign(:payments_page, page)
    |> assign(:payments_end?, length(recent_payments) < per_page)
    |> assign(:payments_empty?, recent_payments == [])
    |> assign(:payments_count, length(recent_payments))
  end

  defp paginate_ledger_entries(socket, page) when page >= 1 do
    %{per_page: per_page, start_date: start_date, end_date: end_date} =
      socket.assigns

    offset = (page - 1) * per_page

    ledger_entries =
      from(e in Ysc.Ledgers.LedgerEntry,
        preload: [:account, :payment, :refund],
        where: e.inserted_at >= ^start_date,
        where: e.inserted_at <= ^end_date,
        order_by: [desc: e.inserted_at],
        limit: ^per_page,
        offset: ^offset
      )
      |> Repo.all()

    socket
    |> assign(:ledger_entries, ledger_entries)
    |> assign(:ledger_entries_page, page)
    |> assign(:ledger_entries_end?, length(ledger_entries) < per_page)
  end

  defp paginate_webhooks(socket, page) when page >= 1 do
    %{per_page: per_page, start_date: start_date, end_date: end_date} =
      socket.assigns

    offset = (page - 1) * per_page

    webhook_events =
      from(w in Ysc.Webhooks.WebhookEvent,
        where: w.provider == "stripe",
        where: w.inserted_at >= ^start_date,
        where: w.inserted_at <= ^end_date,
        order_by: [desc: w.inserted_at],
        limit: ^per_page,
        offset: ^offset
      )
      |> Repo.all()

    socket
    |> assign(:webhook_events, webhook_events)
    |> assign(:webhooks_page, page)
    |> assign(:webhooks_end?, length(webhook_events) < per_page)
  end

  defp paginate_expense_reports(socket, page) when page >= 1 do
    %{per_page: per_page, start_date: start_date, end_date: end_date} =
      socket.assigns

    offset = (page - 1) * per_page

    expense_reports =
      from(er in ExpenseReport,
        where: er.inserted_at >= ^start_date,
        where: er.inserted_at <= ^end_date,
        preload: [:user],
        order_by: [desc: er.inserted_at],
        limit: ^per_page,
        offset: ^offset
      )
      |> Repo.all()

    socket
    |> assign(:expense_reports, expense_reports)
    |> assign(:expense_reports_page, page)
    |> assign(:expense_reports_end?, length(expense_reports) < per_page)
  end

  defp maybe_refresh_expense_reports_list(socket) do
    if socket.assigns.tabs_loaded.expenses do
      paginate_expense_reports(socket, socket.assigns.expense_reports_page)
    else
      socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex flex-col gap-4 py-6 sm:flex-row sm:items-end sm:justify-between">
        <.admin_page_title>Money Management</.admin_page_title>
        <.form
          for={@date_range_form}
          id="money-date-range-form"
          phx-submit="update_date_range"
          class="flex flex-wrap items-end gap-3"
        >
          <.input
            field={@date_range_form[:start_date]}
            type="date"
            label="Start"
            id="start_date"
            class="mt-1 block w-full rounded-md border-zinc-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
          />
          <.input
            field={@date_range_form[:end_date]}
            type="date"
            label="End"
            id="end_date"
            class="mt-1 block w-full rounded-md border-zinc-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
          />
          <.button
            type="submit"
            phx-disable-with="Updating..."
            class="bg-blue-600 hover:bg-blue-700"
          >
            Update
          </.button>
        </.form>
      </div>
      <p class="text-sm text-zinc-500 -mt-2 mb-4">
        Showing data from {format_date_boundary(@start_date)} to {format_date_boundary(
          @end_date
        )}
      </p>

      <.admin_tabs id="money-tabs" aria_label="Money tabs">
        <.admin_tab
          active={@active_tab == :overview}
          patch={money_index_path(assigns, %{"tab" => "overview"})}
        >
          Overview
        </.admin_tab>
        <.admin_tab
          active={@active_tab == :expenses}
          patch={money_index_path(assigns, %{"tab" => "expenses"})}
        >
          Expenses
        </.admin_tab>
        <.admin_tab
          active={@active_tab == :ledger}
          patch={money_index_path(assigns, %{"tab" => "ledger"})}
        >
          Ledger
        </.admin_tab>
        <.admin_tab
          active={@active_tab == :webhooks}
          patch={money_index_path(assigns, %{"tab" => "webhooks"})}
        >
          Webhooks
        </.admin_tab>
      </.admin_tabs>

      <div :if={@active_tab == :overview} id="money-overview-tab">
        <div
          id="expense-reports-inbox"
          class={[
            "mb-6 rounded-lg border shadow-sm px-5 py-4",
            if(@expense_reports_inbox != [],
              do: "bg-rose-50 border-rose-200",
              else: "bg-emerald-50 border-emerald-200"
            )
          ]}
        >
          <%= if @expense_reports_inbox != [] do %>
            <div class="flex flex-wrap items-start justify-between gap-3 mb-4">
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-exclamation-triangle"
                  class="w-6 h-6 text-rose-600 shrink-0 mt-0.5"
                />
                <div>
                  <p class="text-sm font-semibold text-rose-900">
                    Expense reports needing review
                  </p>
                  <p class="text-xs text-rose-700 mt-0.5">
                    {length(@expense_reports_inbox)} submitted report{if length(
                                                                           @expense_reports_inbox
                                                                         ) == 1,
                                                                         do: "",
                                                                         else: "s"} awaiting action
                  </p>
                </div>
              </div>
              <.link
                id="expense-inbox-view-all"
                patch={money_index_path(assigns, %{"tab" => "expenses"})}
                class="text-xs font-semibold text-rose-800 hover:underline shrink-0"
              >
                View all expense reports →
              </.link>
            </div>
            <div class="overflow-x-auto rounded-md border border-rose-100 bg-white">
              <table class="min-w-full divide-y divide-zinc-200">
                <thead class="bg-zinc-50">
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      User
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Purpose
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Submitted
                    </th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-zinc-100">
                  <tr
                    :for={expense_report <- @expense_reports_inbox}
                    id={"expense-inbox-row-#{expense_report.id}"}
                    phx-click="show_expense_report_status_modal"
                    phx-value-expense_report_id={expense_report.id}
                    class="cursor-pointer hover:bg-zinc-50 transition-colors"
                  >
                    <td class="px-4 py-3 text-sm text-zinc-900">
                      <%= if Ecto.assoc_loaded?(expense_report.user) && expense_report.user do %>
                        <div class="flex flex-col">
                          <span class="font-medium">
                            {get_user_display_name(expense_report.user)}
                          </span>
                          <span class="text-xs text-zinc-500">
                            {expense_report.user.email}
                          </span>
                        </div>
                      <% else %>
                        <span class="text-zinc-400">Unknown</span>
                      <% end %>
                    </td>
                    <td class="px-4 py-3 text-sm text-zinc-900 max-w-xs">
                      <div class="truncate" title={expense_report.purpose}>
                        {expense_report.purpose}
                      </div>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                      {format_datetime(
                        expense_report.inserted_at,
                        @timezone,
                        "%Y-%m-%d"
                      )}
                    </td>
                    <td
                      class="px-4 py-3 whitespace-nowrap text-right text-sm"
                      onclick="event.stopPropagation()"
                    >
                      <button
                        type="button"
                        id={"expense-inbox-review-#{expense_report.id}"}
                        phx-click="show_expense_report_status_modal"
                        phx-value-expense_report_id={expense_report.id}
                        class="text-zinc-400 hover:text-blue-600 transition-colors"
                        aria-label="Review expense report"
                      >
                        <.icon name="hero-eye" class="w-5 h-5" />
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% else %>
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div class="flex items-center gap-3">
                <.icon
                  name="hero-check-circle"
                  class="w-7 h-7 text-emerald-600 shrink-0"
                />
                <div>
                  <p class="text-sm font-semibold text-emerald-900">
                    All caught up
                  </p>
                  <p class="text-xs text-emerald-700 mt-0.5">
                    No expense reports waiting for review
                  </p>
                </div>
              </div>
              <.link
                id="expense-inbox-view-all"
                patch={money_index_path(assigns, %{"tab" => "expenses"})}
                class="text-xs font-semibold text-emerald-800 hover:underline shrink-0"
              >
                View all expense reports →
              </.link>
            </div>
          <% end %>
        </div>

        <div
          id="money-kpi-cards"
          class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8"
        >
          <.admin_stat_card
            id="kpi-liquidity"
            label="Liquidity"
            value={Money.to_string!(@liquidity_total)}
            subtitle="Cash + Stripe (as of now)"
          />
          <.admin_stat_card
            id="kpi-period-revenue"
            label="Period Revenue"
            value={Money.to_string!(@period_revenue_total)}
            subtitle="Memberships, events, bookings, donations"
          />
          <.admin_stat_card
            id="kpi-period-expenses"
            label="Period Expenses"
            value={Money.to_string!(@period_expenses_total)}
            subtitle="Stripe fees + discounts"
          />
        </div>

        <div
          id="recent-payments-section"
          class="bg-white shadow-sm border border-zinc-100 rounded-lg overflow-hidden mb-8"
        >
          <div class="px-6 py-4 border-b border-zinc-100">
            <h2 class="text-lg font-semibold text-zinc-900">Recent Payments</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Reference
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    User
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Payment Type
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Amount
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Date
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody
                :if={@loading_money_data || !@tabs_loaded.overview}
                id="recent-payments-loading"
                role="status"
                aria-live="polite"
              >
                <.table_rows_skeleton
                  rows={5}
                  colspan={7}
                  label="Loading recent payments…"
                />
              </tbody>
              <tbody
                :if={
                  @tabs_loaded.overview && !@loading_money_data &&
                    @payments_empty?
                }
                id="recent-payments-empty"
              >
                <tr>
                  <td
                    colspan="7"
                    class="px-6 py-8 text-center text-sm text-zinc-500"
                  >
                    No payments found for the selected date range.
                  </td>
                </tr>
              </tbody>
              <tbody
                id="recent-payments"
                phx-update="stream"
                class={[
                  "bg-white divide-y divide-zinc-200",
                  (!@tabs_loaded.overview || @loading_money_data ||
                     @payments_empty?) && "hidden"
                ]}
              >
                <tr
                  :for={{id, payment} <- @streams.payments}
                  id={id}
                  phx-click={
                    if(payment.payment_type_info.type == "Payout",
                      do: "show_payout_modal",
                      else: "show_payment_modal"
                    )
                  }
                  phx-value-payment_id={payment.id}
                  class="cursor-pointer hover:bg-zinc-50 transition-colors"
                >
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-zinc-900">
                    {payment.reference_id}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <div class="flex flex-col">
                      <span class="font-medium text-zinc-900">
                        {if Ecto.assoc_loaded?(payment.user) && payment.user do
                          get_user_display_name(payment.user)
                        else
                          "System Transaction"
                        end}
                      </span>
                      <span class="text-xs text-zinc-500">
                        {if Ecto.assoc_loaded?(payment.user) && payment.user do
                          payment.user.email
                        else
                          "System Transaction"
                        end}
                      </span>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <div class="flex flex-col">
                      <span class={"font-medium #{get_payment_type_color(payment.payment_type_info.type)}"}>
                        {payment.payment_type_info.type}
                      </span>
                      <span class="text-xs text-zinc-500">
                        {payment.payment_type_info.details}
                      </span>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900 text-right tabular-nums">
                    {Money.to_string!(payment.amount)}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <.badge type={
                      AdminBadgeHelpers.ledger_payment_status_badge_type(
                        payment.status
                      )
                    }>
                      {payment.status}
                    </.badge>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {format_datetime(
                      payment.payment_date,
                      @timezone,
                      "%Y-%m-%d %H:%M"
                    )}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-right">
                    <.row_actions_dropdown
                      id={"payment-actions-#{payment.id}"}
                      label="Payment actions"
                    >
                      <.dropdown_menu_item
                        :if={payment.payment_type_info.type != "Payout"}
                        id={"payment-view-#{payment.id}"}
                        icon="hero-eye"
                        phx-click="show_payment_modal"
                        phx-value-payment_id={payment.id}
                      >
                        View
                      </.dropdown_menu_item>
                      <.dropdown_menu_item
                        :if={payment.payment_type_info.type != "Payout"}
                        id={"payment-refund-#{payment.id}"}
                        icon="hero-arrow-uturn-left"
                        tone={:danger}
                        phx-click="show_refund_modal"
                        phx-value-payment_id={payment.id}
                        disabled={payment.status == :refunded}
                      >
                        Refund
                      </.dropdown_menu_item>
                      <.dropdown_menu_item
                        :if={payment.payment_type_info.type == "Payout"}
                        id={"payment-payout-#{payment.id}"}
                        icon="hero-banknotes"
                        phx-click="show_payout_modal"
                        phx-value-payment_id={payment.id}
                      >
                        Payout Details
                      </.dropdown_menu_item>
                    </.row_actions_dropdown>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <.admin_prev_next_pagination
            page={@payments_page}
            entry_count={@payments_count}
            prev_event="payments_prev-page"
            next_event="payments_next-page"
            prev_disabled?={@payments_page == 1}
            next_disabled?={@payments_end?}
          />
        </div>
      </div>

      <div :if={@active_tab == :expenses} id="money-expenses-tab">
        <div class="bg-white shadow-sm border border-zinc-100 rounded-lg overflow-hidden mb-8">
          <div class="px-6 py-4 border-b border-zinc-100">
            <h2 class="text-lg font-semibold text-zinc-900">Expense Reports</h2>
            <p class="text-sm text-zinc-500 mt-1">
              All reports in the selected date range
            </p>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    ID
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    User
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Purpose
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    <span class="block max-w-[7rem] whitespace-normal leading-tight">
                      QuickBooks Sync Status
                    </span>
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    <span class="block max-w-[7rem] whitespace-normal leading-tight">
                      QuickBooks Bill ID
                    </span>
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Submitted At
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr
                  :for={expense_report <- @expense_reports}
                  id={"expense-report-row-#{expense_report.id}"}
                  phx-click="show_expense_report_status_modal"
                  phx-value-expense_report_id={expense_report.id}
                  class="cursor-pointer hover:bg-zinc-50 transition-colors"
                >
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-zinc-900">
                    {String.slice(to_string(expense_report.id), 0..12)}...
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <%= if Ecto.assoc_loaded?(expense_report.user) && expense_report.user do %>
                      <div class="flex flex-col">
                        <span class="font-medium text-zinc-900">
                          {get_user_display_name(expense_report.user)}
                        </span>
                        <span class="text-xs text-zinc-500">
                          {expense_report.user.email}
                        </span>
                      </div>
                    <% else %>
                      <span class="text-zinc-400">Unknown</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 text-sm text-zinc-900 max-w-xs">
                    <div class="truncate" title={expense_report.purpose}>
                      {expense_report.purpose}
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <.badge type={
                      AdminBadgeHelpers.expense_report_status_badge_type(
                        expense_report.status
                      )
                    }>
                      {String.capitalize(expense_report.status || "unknown")}
                    </.badge>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <.admin_quickbooks_sync_status
                      status={expense_report.quickbooks_sync_status}
                      error={expense_report.quickbooks_sync_error}
                      default_label="unknown"
                    />
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                    <%= if expense_report.quickbooks_bill_id do %>
                      <span class="font-mono text-xs">
                        {String.slice(expense_report.quickbooks_bill_id, 0..20)}...
                      </span>
                    <% else %>
                      <span class="text-zinc-400">—</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {format_datetime(
                      expense_report.inserted_at,
                      @timezone,
                      "%Y-%m-%d %H:%M"
                    )}
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-sm font-medium text-right"
                    onclick="event.stopPropagation()"
                  >
                    <button
                      type="button"
                      id={"expense-report-view-#{expense_report.id}"}
                      phx-click="show_expense_report_status_modal"
                      phx-value-expense_report_id={expense_report.id}
                      class="text-zinc-400 hover:text-blue-600 transition-colors"
                      aria-label="View expense report"
                    >
                      <.icon name="hero-eye" class="w-5 h-5" />
                    </button>
                  </td>
                </tr>
                <tr :if={Enum.empty?(@expense_reports)}>
                  <td
                    colspan="8"
                    class="px-6 py-4 text-center text-sm text-zinc-500"
                  >
                    No expense reports found for the selected date range.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <.admin_prev_next_pagination
            page={@expense_reports_page}
            entry_count={length(@expense_reports)}
            prev_event="expense_reports_prev-page"
            next_event="expense_reports_next-page"
            prev_disabled?={@expense_reports_page == 1}
            next_disabled?={@expense_reports_end?}
          />
        </div>
      </div>

      <div :if={@active_tab == :ledger} id="money-ledger-tab">
        <div class="mb-8">
          <h2 class="text-lg font-semibold text-zinc-900 mb-4">
            Account Balances
          </h2>
          <div
            :if={!@tabs_loaded.ledger}
            id="account-balances-loading"
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
            role="status"
            aria-live="polite"
          >
            <span class="sr-only">Loading account balances…</span>
            <div
              :for={_ <- 1..6}
              class="bg-white p-4 rounded-lg shadow-sm border border-zinc-100 space-y-3"
            >
              <div class="flex justify-between items-start">
                <.skeleton_block class="h-4 w-28 rounded" />
                <.skeleton_block class="h-3 w-16 rounded" />
              </div>
              <.skeleton_block class="h-3 w-full rounded" />
              <.skeleton_block class="h-7 w-24 rounded" />
            </div>
          </div>
          <div
            :if={@tabs_loaded.ledger}
            id="account-balances-grid"
            class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
          >
            <div
              :for={account_data <- @accounts_with_balances}
              class="bg-white p-4 rounded-lg shadow-sm border border-zinc-100"
            >
              <div class="flex justify-between items-start mb-2">
                <h3 class="font-medium text-zinc-900">
                  {account_data.account.name}
                </h3>
                <span class="text-[10px] text-zinc-400 uppercase tracking-wide">
                  {String.capitalize(
                    to_string(account_data.account.normal_balance || "debit")
                  )}-normal
                </span>
              </div>
              <p class="text-sm text-zinc-600 mb-3">
                {account_data.account.description}
              </p>
              <p class={"text-2xl font-semibold #{get_balance_color(account_data.balance, account_data.account.normal_balance)}"}>
                {Money.to_string!(account_data.balance || Money.new(0, :USD))}
              </p>
              <p class="text-xs text-zinc-500 capitalize mt-1">
                {account_data.account.account_type}
              </p>
            </div>
          </div>
        </div>

        <div class="bg-white shadow-sm border border-zinc-100 rounded-lg overflow-hidden mb-8">
          <div class="px-6 py-4 border-b border-zinc-100">
            <h2 class="text-lg font-semibold text-zinc-900">Ledger Entries</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Date
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Account
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Description
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Debit/Credit
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Amount
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Payment
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Refund
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Entity
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={entry <- @ledger_entries}>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {format_datetime(
                      entry.inserted_at,
                      @timezone,
                      "%Y-%m-%d %H:%M"
                    )}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <div class="flex flex-col">
                      <span class="font-medium text-zinc-900">
                        {entry.account.name}
                      </span>
                      <span class="text-xs text-zinc-500">
                        {String.capitalize(to_string(entry.account.account_type))}
                      </span>
                    </div>
                  </td>
                  <td class="px-6 py-4 text-sm text-zinc-900 max-w-xs">
                    <div class="truncate" title={entry.description}>
                      {entry.description}
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_debit_credit_badge_color(entry.debit_credit)}"}>
                      {String.capitalize(to_string(entry.debit_credit))}
                    </span>
                  </td>
                  <td class={"px-6 py-4 whitespace-nowrap text-sm font-medium text-right tabular-nums #{get_debit_credit_amount_color(entry.debit_credit)}"}>
                    {Money.to_string!(entry.amount)}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                    <%= if entry.payment do %>
                      <span class="font-mono text-xs">
                        {entry.payment.reference_id}
                      </span>
                    <% else %>
                      <span class="text-zinc-400">—</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                    <%= if entry.refund do %>
                      <span class="font-mono text-xs">
                        {entry.refund.reference_id}
                      </span>
                    <% else %>
                      <span class="text-zinc-400">—</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                    <%= if entry.related_entity_type do %>
                      <div class="flex flex-col">
                        <span class="text-xs font-medium text-zinc-700">
                          {String.capitalize(to_string(entry.related_entity_type))}
                        </span>
                        <%= if entry.related_entity_id do %>
                          <span class="text-xs font-mono text-zinc-500">
                            {String.slice(to_string(entry.related_entity_id), 0..8)}...
                          </span>
                        <% end %>
                      </div>
                    <% else %>
                      <span class="text-zinc-400">—</span>
                    <% end %>
                  </td>
                </tr>
                <tr :if={Enum.empty?(@ledger_entries)}>
                  <td
                    colspan="8"
                    class="px-6 py-4 text-center text-sm text-zinc-500"
                  >
                    No ledger entries found for the selected date range.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <.admin_prev_next_pagination
            page={@ledger_entries_page}
            entry_count={length(@ledger_entries)}
            prev_event="ledger_entries_prev-page"
            next_event="ledger_entries_next-page"
            prev_disabled?={@ledger_entries_page == 1}
            next_disabled?={@ledger_entries_end?}
          />
        </div>
      </div>

      <div :if={@active_tab == :webhooks} id="money-webhooks-tab">
        <div class="bg-white shadow-sm border border-zinc-100 rounded-lg overflow-hidden mb-8">
          <div class="px-6 py-4 border-b border-zinc-100">
            <h2 class="text-lg font-semibold text-zinc-900">
              Stripe Webhook Events
            </h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Event ID
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Event Type
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    State
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Received At
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-zinc-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr
                  :for={webhook <- @webhook_events}
                  id={"webhook-row-#{webhook.id}"}
                  phx-click="show_webhook_modal"
                  phx-value-webhook_id={webhook.id}
                  class="cursor-pointer hover:bg-zinc-50 transition-colors"
                >
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-zinc-900">
                    {String.slice(webhook.event_id, 0..20)}...
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    <span class="font-medium">{webhook.event_type}</span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_webhook_state_color(webhook.state)}"}>
                      {webhook.state}
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                    {format_datetime(
                      webhook.inserted_at,
                      @timezone,
                      "%Y-%m-%d %H:%M:%S"
                    )}
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-sm font-medium text-right"
                    onclick="event.stopPropagation()"
                  >
                    <button
                      type="button"
                      id={"webhook-view-#{webhook.id}"}
                      phx-click="show_webhook_modal"
                      phx-value-webhook_id={webhook.id}
                      class="text-zinc-400 hover:text-blue-600 transition-colors"
                      aria-label="View webhook details"
                    >
                      <.icon name="hero-eye" class="w-5 h-5" />
                    </button>
                  </td>
                </tr>
                <tr :if={Enum.empty?(@webhook_events)}>
                  <td
                    colspan="5"
                    class="px-6 py-4 text-center text-sm text-zinc-500"
                  >
                    No webhook events found for the selected date range.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <.admin_prev_next_pagination
            page={@webhooks_page}
            entry_count={length(@webhook_events)}
            prev_event="webhooks_prev-page"
            next_event="webhooks_next-page"
            prev_disabled?={@webhooks_page == 1}
            next_disabled?={@webhooks_end?}
          />
        </div>
      </div>

      <!-- Refund Modal -->
      <.modal
        :if={@live_action == :refund_payment && @selected_payment}
        id="refund-modal"
        show
        on_cancel={JS.push("close_refund_modal")}
      >
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Process Refund</h3>

        <div class="mb-4">
          <p class="text-sm text-zinc-600">
            <strong>Payment:</strong> {@selected_payment.reference_id}
          </p>
          <p class="text-sm text-zinc-600">
            <strong>Amount:</strong> {Money.to_string!(@selected_payment.amount)}
          </p>
          <p :if={@selected_payment.user} class="text-sm text-zinc-600">
            <strong>User:</strong>
            <.link
              navigate={~p"/admin/users/#{@selected_payment.user.id}/details"}
              class="text-blue-600 hover:underline"
            >
              {@selected_payment.user.email}
            </.link>
          </p>
        </div>

        <.form
          for={@refund_form}
          id="refund-form"
          phx-submit="process_refund"
          phx-change="validate_refund"
        >
          <!-- Ticket Selection for Ticket Orders -->
          <div
            :if={@ticket_order}
            class="mb-4 p-4 bg-blue-50 rounded border border-blue-200"
          >
            <h4 class="text-sm font-semibold text-zinc-800 mb-3">
              Select Tickets to Refund
            </h4>
            <p class="text-xs text-zinc-600 mb-3">
              Only selected tickets will be refunded and returned to stock.
            </p>
            <div class="space-y-2 max-h-64 overflow-y-auto">
              <label
                :for={
                  ticket <-
                    (@ticket_order.tickets || [])
                    |> Enum.filter(&(&1.status in [:confirmed, :pending]))
                }
                class="flex items-start p-2 border border-zinc-200 rounded hover:bg-blue-100 cursor-pointer"
              >
                <input
                  type="checkbox"
                  name="refund[ticket_ids][]"
                  value={ticket.id}
                  class="mt-1 mr-3"
                  checked={
                    ticket_id_str = to_string(ticket.id)

                    # Get ticket_ids from changeset changes first, then from params, then from data
                    ticket_ids =
                      case Ecto.Changeset.get_change(
                             @refund_form.source,
                             :ticket_ids
                           ) do
                        nil ->
                          # Try to get from params (for form state)
                          case @refund_form.source.params do
                            %{"ticket_ids" => ids} when is_list(ids) ->
                              ids

                            _ ->
                              # Fall back to data
                              case Ecto.Changeset.get_field(
                                     @refund_form.source,
                                     :ticket_ids
                                   ) do
                                nil -> []
                                ids when is_list(ids) -> ids
                                _ -> []
                              end
                          end

                        ids when is_list(ids) ->
                          ids

                        _ ->
                          []
                      end

                    ticket_id_str in Enum.map(ticket_ids, &to_string/1)
                  }
                />
                <div class="flex-1">
                  <div class="text-sm font-medium text-zinc-900">
                    {ticket.ticket_tier.name}
                  </div>
                  <div class="text-xs text-zinc-600">
                    Ticket ID: {ticket.reference_id || ticket.id}
                  </div>
                  <div class="text-xs font-medium text-zinc-700 mt-1">
                    {cond do
                      ticket.ticket_tier.type == :free ->
                        "Free"

                      ticket.ticket_tier.type == :donation ->
                        "Donation"

                      true ->
                        Money.to_string!(
                          ticket.ticket_tier.price || Money.new(0, :USD)
                        )
                    end}
                  </div>
                </div>
              </label>
            </div>
            <p
              :if={
                (@ticket_order.tickets || [])
                |> Enum.filter(&(&1.status in [:confirmed, :pending]))
                |> length() == 0
              }
              class="text-sm text-zinc-500 italic"
            >
              No refundable tickets found (all tickets are already cancelled or expired).
            </p>
          </div>
          <div class="mb-4">
            <.input
              field={@refund_form[:amount]}
              type="text"
              label="Refund Amount"
              placeholder="e.g., 25.00"
              required
            />
            <p :if={@ticket_order} class="text-xs text-zinc-500 mt-1">
              Amount will be calculated automatically when you select tickets above.
            </p>
          </div>

          <div class="mb-4">
            <.input
              field={@refund_form[:reason]}
              type="textarea"
              label="Reason for Refund"
              placeholder="Enter reason for refund..."
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@refund_form[:release_availability]}
              type="checkbox"
              label="Release tickets/booking for others to purchase"
            />
          </div>

          <div class="flex justify-end gap-2">
            <.button
              type="button"
              phx-click="close_refund_modal"
              class="bg-zinc-500 hover:bg-zinc-600"
            >
              Cancel
            </.button>
            <.button
              type="submit"
              phx-disable-with="Processing..."
              class="bg-red-600 hover:bg-red-700"
            >
              Process Refund
            </.button>
          </div>
        </.form>
      </.modal>
      <!-- Credit Modal -->
      <.modal
        :if={@show_credit_modal}
        id="credit-modal"
        show
        on_cancel={JS.push("close_credit_modal")}
      >
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Add Credit</h3>

        <div :if={@selected_user} class="mb-4">
          <p class="text-sm text-zinc-600">
            <strong>User:</strong>
            <.link
              navigate={~p"/admin/users/#{@selected_user.id}/details"}
              class="text-blue-600 hover:underline"
            >
              {@selected_user.email}
            </.link>
          </p>
        </div>

        <.form
          for={@credit_form}
          id="credit-form"
          phx-submit="process_credit"
          phx-change="validate_credit"
        >
          <div :if={!@selected_user} class="mb-4">
            <.input
              field={@credit_form[:user_id]}
              type="text"
              label="User ID"
              placeholder="Enter user ID"
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@credit_form[:amount]}
              type="text"
              label="Credit Amount"
              placeholder="e.g., 50.00"
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@credit_form[:reason]}
              type="textarea"
              label="Reason for Credit"
              placeholder="Enter reason for credit..."
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@credit_form[:entity_type]}
              type="select"
              label="Entity Type"
              options={[
                {"Administration", "administration"},
                {"Event", "event"},
                {"Membership", "membership"},
                {"Booking", "booking"},
                {"Donation", "donation"}
              ]}
            />
          </div>

          <div class="mb-4">
            <.input
              field={@credit_form[:entity_id]}
              type="text"
              label="Entity ID (Optional)"
              placeholder="Enter entity ID if applicable"
            />
          </div>

          <div class="flex justify-end gap-2">
            <.button
              type="button"
              phx-click="close_credit_modal"
              class="bg-zinc-500 hover:bg-zinc-600"
            >
              Cancel
            </.button>
            <.button
              type="submit"
              phx-disable-with="Adding..."
              class="bg-green-600 hover:bg-green-700"
            >
              Add Credit
            </.button>
          </div>
        </.form>
      </.modal>
      <!-- Webhook Details Modal -->
      <.modal
        :if={@show_webhook_modal && @selected_webhook}
        id="webhook-modal"
        show
        on_cancel={JS.push("close_webhook_modal")}
      >
        <h3 class="text-lg font-medium text-zinc-900 mb-4">
          Webhook Event Details
        </h3>

        <div class="mb-4 space-y-2">
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Event ID:</strong>
              <span class="text-zinc-600 font-mono text-xs ml-2">
                {@selected_webhook.event_id}
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Event Type:</strong>
              <span class="text-zinc-600 ml-2">
                {@selected_webhook.event_type}
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Provider:</strong>
              <span class="text-zinc-600 ml-2 capitalize">
                {@selected_webhook.provider}
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">State:</strong>
              <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full ml-2 #{get_webhook_state_color(@selected_webhook.state)}"}>
                {@selected_webhook.state}
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Received At:</strong>
              <span class="text-zinc-600 ml-2">
                {format_datetime(
                  @selected_webhook.inserted_at,
                  @timezone,
                  "%Y-%m-%d %H:%M:%S"
                )}
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Last Updated:</strong>
              <span class="text-zinc-600 ml-2">
                {format_datetime(
                  @selected_webhook.updated_at,
                  @timezone,
                  "%Y-%m-%d %H:%M:%S"
                )}
              </span>
            </p>
          </div>
        </div>

        <div class="mb-4">
          <label class="block text-sm font-medium text-zinc-900 mb-2">
            Payload
          </label>
          <pre class="bg-zinc-50 border border-zinc-200 rounded p-4 text-xs overflow-auto max-h-96 font-mono text-zinc-800"><%= Jason.encode!(@selected_webhook.payload, pretty: true) %></pre>
        </div>

        <div class="flex justify-end gap-2">
          <.button
            type="button"
            phx-click="close_webhook_modal"
            class="bg-zinc-500 hover:bg-zinc-600"
          >
            Close
          </.button>
        </div>
      </.modal>
      <!-- Payout Details Modal -->
      <.modal
        :if={@live_action == :view_payout && @selected_payout}
        id="payout-modal"
        max_width="max-w-7xl"
        show
        on_cancel={JS.push("close_payout_modal")}
      >
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Payout Details</h3>

        <div class="mb-6 space-y-3">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-sm font-medium text-zinc-700">Stripe Payout ID</p>
              <div class="flex flex-wrap items-center gap-2 min-w-0">
                <a
                  href={"https://dashboard.stripe.com/payouts/#{@selected_payout.stripe_payout_id}"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-sm text-zinc-900 hover:text-blue-600 font-mono transition-colors underline decoration-dotted break-all min-w-0"
                  title="View in Stripe Dashboard"
                >
                  {@selected_payout.stripe_payout_id}
                </a>
                <.admin_clipboard_button
                  id={"copy-stripe-payout-#{@selected_payout.id}"}
                  variant={:icon}
                  copy={@selected_payout.stripe_payout_id}
                  title="Copy Stripe Payout ID"
                  aria_label="Copy Stripe Payout ID"
                />
              </div>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Status</p>
              <.badge type={
                AdminBadgeHelpers.payout_status_badge_type(@selected_payout.status)
              }>
                {String.capitalize(@selected_payout.status || "unknown")}
              </.badge>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Payout Amount</p>
              <p class="text-sm text-zinc-900 font-semibold">
                {Money.to_string!(@selected_payout.amount)}
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Total Fees</p>
              <p class="text-sm  font-semibold text-red-600">
                {Money.to_string!(@selected_payout.fee_total || Money.new(0, :USD))}
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Arrival Date</p>
              <p class="text-sm text-zinc-900">
                <%= if @selected_payout.arrival_date do %>
                  {format_datetime(
                    @selected_payout.arrival_date,
                    @timezone,
                    "%Y-%m-%d %H:%M"
                  )}
                <% else %>
                  N/A
                <% end %>
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Created</p>
              <p class="text-sm text-zinc-900">
                {format_datetime(
                  @selected_payout.inserted_at,
                  @timezone,
                  "%Y-%m-%d %H:%M"
                )}
              </p>
            </div>
          </div>
        </div>
        <!-- QuickBooks Information -->
        <div class="mb-6 p-4 bg-amber-50 rounded border border-amber-200">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            QuickBooks Information
          </h4>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p class="font-medium text-zinc-700">Sync Status</p>
              <p class="text-zinc-900">
                <.admin_quickbooks_sync_status
                  status={@selected_payout.quickbooks_sync_status}
                  layout={:inline}
                />
              </p>
            </div>
            <%= if @selected_payout.quickbooks_deposit_id do %>
              <div>
                <p class="font-medium text-zinc-700">QuickBooks Deposit ID</p>
                <a
                  href={
                    quickbooks_entity_url(
                      "deposit",
                      @selected_payout.quickbooks_deposit_id
                    )
                  }
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-zinc-900 hover:text-blue-600 font-mono text-xs transition-colors underline decoration-dotted"
                  title="View in QuickBooks"
                >
                  {@selected_payout.quickbooks_deposit_id}
                </a>
              </div>
            <% end %>
            <%= if @selected_payout.quickbooks_synced_at do %>
              <div>
                <p class="font-medium text-zinc-700">Synced At</p>
                <p class="text-zinc-900 text-xs">
                  {format_datetime(
                    @selected_payout.quickbooks_synced_at,
                    @timezone,
                    "%Y-%m-%d %H:%M:%S"
                  )}
                </p>
              </div>
            <% end %>
            <%= if @selected_payout.quickbooks_last_sync_attempt_at do %>
              <div>
                <p class="font-medium text-zinc-700">Last Sync Attempt</p>
                <p class="text-zinc-900 text-xs">
                  {format_datetime(
                    @selected_payout.quickbooks_last_sync_attempt_at,
                    @timezone,
                    "%Y-%m-%d %H:%M:%S"
                  )}
                </p>
              </div>
            <% end %>
            <%= if @selected_payout.quickbooks_sync_error do %>
              <div class="col-span-2">
                <p class="font-medium text-zinc-700">Sync Error</p>
                <.tooltip
                  tooltip_text={
                    format_quickbooks_sync_error(
                      @selected_payout.quickbooks_sync_error
                    )
                  }
                  max_width="max-w-md"
                  text_align="text-left"
                >
                  <p class="text-red-600 text-xs cursor-help">
                    {format_quickbooks_sync_error(
                      @selected_payout.quickbooks_sync_error
                    )}
                  </p>
                </.tooltip>
              </div>
            <% end %>
            <%= if !@selected_payout.quickbooks_deposit_id && !@selected_payout.quickbooks_sync_status do %>
              <div class="col-span-2">
                <p class="text-zinc-500 text-xs italic">
                  Not yet synced to QuickBooks
                </p>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Associated Payments -->
        <div class="mb-6">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            Associated Payments ({length(@selected_payout.payments || [])})
          </h4>
          <div
            :if={length(@selected_payout.payments || []) > 0}
            class="overflow-x-auto"
          >
            <table class="min-w-full divide-y divide-zinc-200 text-sm">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    Reference
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    User
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    Amount
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    Status
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    QB Status
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    Date
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={payment <- @selected_payout.payments}>
                  <td class="px-4 py-2 whitespace-nowrap font-mono text-xs">
                    {payment.reference_id}
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <%= if Ecto.assoc_loaded?(payment.user) && payment.user do %>
                      <.link
                        navigate={~p"/admin/users/#{payment.user.id}/details"}
                        class="flex flex-col group"
                      >
                        <span class="text-xs font-medium text-blue-600 group-hover:underline">
                          {get_user_display_name(payment.user)}
                        </span>
                        <span class="text-xs text-zinc-500 group-hover:underline">
                          {payment.user.email}
                        </span>
                      </.link>
                    <% else %>
                      <span class="text-xs text-zinc-400">System</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap font-medium">
                    {Money.to_string!(payment.amount)}
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <.badge type={
                      AdminBadgeHelpers.ledger_payment_status_badge_type(
                        payment.status
                      )
                    }>
                      {String.capitalize(to_string(payment.status))}
                    </.badge>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <.admin_quickbooks_sync_status
                      status={payment.quickbooks_sync_status}
                      error={payment.quickbooks_sync_error}
                      error_hint={:label}
                    />
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap text-xs">
                    {format_datetime(
                      payment.payment_date,
                      @timezone,
                      "%Y-%m-%d %H:%M"
                    )}
                  </td>
                </tr>
              </tbody>
            </table>
            <!-- Total Payments -->
            <div class="px-6 py-3 bg-zinc-50 border-t border-zinc-200">
              <div class="flex justify-between items-center">
                <span class="text-sm font-semibold text-zinc-700">
                  Total Payments:
                </span>
                <span class="text-sm font-bold text-zinc-900">
                  {Money.to_string!(
                    @selected_payout.payments
                    |> Enum.reduce(Money.new(0, :USD), fn payment, acc ->
                      case Money.add(acc, payment.amount) do
                        {:ok, total} -> total
                        {:error, _} -> acc
                      end
                    end)
                  )}
                </span>
              </div>
            </div>
          </div>
          <p
            :if={length(@selected_payout.payments || []) == 0}
            class="text-sm text-zinc-500 italic"
          >
            No payments associated with this payout.
          </p>
        </div>
        <!-- Associated Refunds -->
        <div class="mb-6">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            Associated Refunds ({length(@selected_payout.refunds || [])})
          </h4>
          <div
            :if={length(@selected_payout.refunds || []) > 0}
            class="overflow-x-auto"
          >
            <table class="min-w-full divide-y divide-zinc-200 text-sm">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    Reference
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    User
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    Amount
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    Reason
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    Status
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    QB Status
                  </th>
                  <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                    Date
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={refund <- @selected_payout.refunds}>
                  <td class="px-4 py-2 whitespace-nowrap font-mono text-xs">
                    {refund.reference_id}
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <%= if Ecto.assoc_loaded?(refund.user) && refund.user do %>
                      <.link
                        navigate={~p"/admin/users/#{refund.user.id}/details"}
                        class="flex flex-col group"
                      >
                        <span class="text-xs font-medium text-blue-600 group-hover:underline">
                          {get_user_display_name(refund.user)}
                        </span>
                        <span class="text-xs text-zinc-500 group-hover:underline">
                          {refund.user.email}
                        </span>
                      </.link>
                    <% else %>
                      <span class="text-xs text-zinc-400">System</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap font-medium text-red-600">
                    {Money.to_string!(refund.amount)}
                  </td>
                  <td class="px-4 py-2 text-xs text-zinc-600 max-w-xs">
                    <div class="truncate" title={refund.reason}>
                      {refund.reason || "N/A"}
                    </div>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <.badge type={
                      AdminBadgeHelpers.ledger_payment_status_badge_type(
                        refund.status
                      )
                    }>
                      {String.capitalize(to_string(refund.status))}
                    </.badge>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <.admin_quickbooks_sync_status
                      status={refund.quickbooks_sync_status}
                      error={refund.quickbooks_sync_error}
                      error_hint={:label}
                    />
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap text-xs">
                    {format_datetime(
                      refund.inserted_at,
                      @timezone,
                      "%Y-%m-%d %H:%M"
                    )}
                  </td>
                </tr>
              </tbody>
            </table>
            <!-- Total Refunds -->
            <div class="px-6 py-3 bg-zinc-50 border-t border-zinc-200">
              <div class="flex justify-between items-center">
                <span class="text-sm font-semibold text-zinc-700">
                  Total Refunds:
                </span>
                <span class="text-sm font-bold text-red-600">
                  {Money.to_string!(
                    @selected_payout.refunds
                    |> Enum.reduce(Money.new(0, :USD), fn refund, acc ->
                      case Money.add(acc, refund.amount) do
                        {:ok, total} -> total
                        {:error, _} -> acc
                      end
                    end)
                  )}
                </span>
              </div>
            </div>
          </div>
          <p
            :if={length(@selected_payout.refunds || []) == 0}
            class="text-sm text-zinc-500 italic"
          >
            No refunds associated with this payout.
          </p>
        </div>
        <!-- Summary -->
        <%!-- Compute totals once so we can show reconciliation math --%>
        <% payout_total_payments =
          (@selected_payout.payments || [])
          |> Enum.reduce(Money.new(0, :USD), fn p, acc ->
            case Money.add(acc, p.amount) do
              {:ok, total} -> total
              {:error, _} -> acc
            end
          end)

        payout_total_refunds =
          (@selected_payout.refunds || [])
          |> Enum.reduce(Money.new(0, :USD), fn r, acc ->
            case Money.add(acc, r.amount) do
              {:ok, total} -> total
              {:error, _} -> acc
            end
          end)

        payout_fees = @selected_payout.fee_total || Money.new(0, :USD)

        payout_computed_net =
          with {:ok, after_refunds} <-
                 Money.sub(payout_total_payments, payout_total_refunds),
               {:ok, net} <- Money.sub(after_refunds, payout_fees) do
            net
          else
            _ -> Money.new(0, :USD)
          end

        payout_reconciles? =
          payout_computed_net == @selected_payout.amount %>
        <div class="mb-4 p-4 bg-zinc-50 rounded border">
          <h4 class="text-sm font-semibold text-zinc-800 mb-2">Summary</h4>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p class="text-zinc-600">Total Payments (gross):</p>
              <p class="font-semibold text-zinc-900">
                {Money.to_string!(payout_total_payments)}
              </p>
            </div>
            <div>
              <p class="text-zinc-600">Total Refunds:</p>
              <p class="font-semibold text-red-600">
                {Money.to_string!(payout_total_refunds)}
              </p>
            </div>
            <div>
              <p class="text-zinc-600">Stripe Fees:</p>
              <p class="font-semibold text-red-600">
                {Money.to_string!(payout_fees)}
              </p>
            </div>
            <div>
              <p class="text-zinc-600">Bank Transfer (Stripe net):</p>
              <p class="font-semibold text-zinc-900">
                {Money.to_string!(@selected_payout.amount)}
              </p>
            </div>
          </div>
          <%!-- Reconciliation row: computed net must equal the Stripe payout amount --%>
          <div class="mt-3 pt-3 border-t border-zinc-200">
            <div class="flex items-center justify-between">
              <span class="text-xs text-zinc-500">
                Gross − Refunds − Fees =
                <span class="font-mono">
                  {Money.to_string!(payout_computed_net)}
                </span>
              </span>
              <%= if payout_reconciles? do %>
                <.badge type="green">Reconciled ✓</.badge>
              <% else %>
                <.badge type="red">
                  Mismatch — some charges may not be linked yet
                </.badge>
              <% end %>
            </div>
          </div>
        </div>

        <div class="flex justify-end gap-2">
          <%= if @selected_payout.quickbooks_sync_status != "synced" do %>
            <.button
              id="retry-payout-qb-sync-btn"
              type="button"
              phx-click="retry_payout_qb_sync"
              phx-value-payout_id={@selected_payout.id}
              class="bg-amber-600 hover:bg-amber-700"
            >
              Retry QB Sync
            </.button>
          <% end %>
          <.button
            type="button"
            phx-click="close_payout_modal"
            class="bg-zinc-500 hover:bg-zinc-600"
          >
            Close
          </.button>
        </div>
      </.modal>
      <!-- Payment Details Modal -->
      <.modal
        :if={@live_action == :view_payment && @selected_payment}
        id="payment-modal"
        show
        on_cancel={JS.push("close_payment_modal")}
      >
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Payment Details</h3>

        <div class="mb-6 space-y-4">
          <!-- Payment Information -->
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-sm font-medium text-zinc-700">Reference ID</p>
              <p class="text-sm text-zinc-900 font-mono">
                {@selected_payment.reference_id}
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Status</p>
              <.badge type={
                AdminBadgeHelpers.ledger_payment_status_badge_type(
                  @selected_payment.status
                )
              }>
                {String.capitalize(to_string(@selected_payment.status || "unknown"))}
              </.badge>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Amount</p>
              <p class="text-sm text-zinc-900 font-semibold">
                {Money.to_string!(@selected_payment.amount)}
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Payment Date</p>
              <p class="text-sm text-zinc-900">
                {format_datetime(
                  @selected_payment.payment_date,
                  @timezone,
                  "%Y-%m-%d %H:%M"
                )}
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">User</p>
              <p class="text-sm text-zinc-900">
                <%= if Ecto.assoc_loaded?(@selected_payment.user) && @selected_payment.user do %>
                  <.link
                    navigate={~p"/admin/users/#{@selected_payment.user.id}/details"}
                    class="flex flex-col group"
                  >
                    <span class="font-medium text-blue-600 group-hover:underline">
                      {get_user_display_name(@selected_payment.user)}
                    </span>
                    <span class="text-xs text-zinc-500 group-hover:underline">
                      {@selected_payment.user.email}
                    </span>
                  </.link>
                <% else %>
                  <span class="text-zinc-400">System</span>
                <% end %>
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Payment Type</p>
              <p class="text-sm text-zinc-900">
                <%= if @selected_payment.payment_type_info do %>
                  <span class={"font-medium #{get_payment_type_color(@selected_payment.payment_type_info.type)}"}>
                    {@selected_payment.payment_type_info.type}
                  </span>
                  <%= if @selected_payment.payment_type_info.details do %>
                    <span class="text-xs text-zinc-500 block mt-1">
                      {@selected_payment.payment_type_info.details}
                    </span>
                  <% end %>
                <% else %>
                  <span class="text-zinc-400">Unknown</span>
                <% end %>
              </p>
            </div>
            <div :if={@selected_payment.external_payment_id}>
              <p class="text-sm font-medium text-zinc-700">Stripe Payment ID</p>
              <div class="flex flex-wrap items-center gap-2 min-w-0">
                <a
                  href={"https://dashboard.stripe.com/payments/#{@selected_payment.external_payment_id}"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-xs text-zinc-900 hover:text-blue-600 font-mono transition-colors underline decoration-dotted break-all min-w-0"
                  title="View in Stripe Dashboard"
                >
                  {@selected_payment.external_payment_id}
                </a>
                <.admin_clipboard_button
                  id={"copy-stripe-payment-#{@selected_payment.id}"}
                  variant={:icon}
                  copy={@selected_payment.external_payment_id}
                  title="Copy Stripe Payment ID"
                  aria_label="Copy Stripe Payment ID"
                />
              </div>
            </div>
          </div>
          <!-- QuickBooks Information -->
          <div class="mt-4 p-4 bg-amber-50 rounded border border-amber-200">
            <h4 class="text-sm font-semibold text-zinc-800 mb-3">
              QuickBooks Information
            </h4>
            <div class="grid grid-cols-2 gap-4 text-sm">
              <div>
                <p class="font-medium text-zinc-700">Sync Status</p>
                <p class="text-zinc-900">
                  <.admin_quickbooks_sync_status
                    status={@selected_payment.quickbooks_sync_status}
                    layout={:inline}
                  />
                </p>
              </div>
              <%= if @selected_payment.quickbooks_sales_receipt_id do %>
                <div>
                  <p class="font-medium text-zinc-700">Sales Receipt ID</p>
                  <a
                    href={
                      quickbooks_entity_url(
                        "salesreceipt",
                        @selected_payment.quickbooks_sales_receipt_id
                      )
                    }
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-zinc-900 hover:text-blue-600 font-mono text-xs transition-colors underline decoration-dotted"
                    title="View in QuickBooks"
                  >
                    {@selected_payment.quickbooks_sales_receipt_id}
                  </a>
                </div>
              <% end %>
              <%= if @selected_payment.quickbooks_synced_at do %>
                <div>
                  <p class="font-medium text-zinc-700">Synced At</p>
                  <p class="text-zinc-900 text-xs">
                    {format_datetime(
                      @selected_payment.quickbooks_synced_at,
                      @timezone,
                      "%Y-%m-%d %H:%M:%S"
                    )}
                  </p>
                </div>
              <% end %>
              <%= if @selected_payment.quickbooks_last_sync_attempt_at do %>
                <div>
                  <p class="font-medium text-zinc-700">Last Sync Attempt</p>
                  <p class="text-zinc-900 text-xs">
                    {format_datetime(
                      @selected_payment.quickbooks_last_sync_attempt_at,
                      @timezone,
                      "%Y-%m-%d %H:%M:%S"
                    )}
                  </p>
                </div>
              <% end %>
              <%= if @selected_payment.quickbooks_sync_error do %>
                <div class="col-span-2">
                  <p class="font-medium text-zinc-700">Sync Error</p>
                  <p class="text-red-600 text-xs">
                    {format_quickbooks_sync_error(
                      @selected_payment.quickbooks_sync_error
                    )}
                  </p>
                </div>
              <% end %>
              <%= if !@selected_payment.quickbooks_sales_receipt_id && !@selected_payment.quickbooks_sync_status do %>
                <div class="col-span-2">
                  <p class="text-zinc-500 text-xs italic">
                    Not yet synced to QuickBooks
                  </p>
                </div>
              <% end %>
            </div>
          </div>
          <!-- Related Entity -->
          <div
            :if={@payment_related_entity}
            class="mt-4 p-4 bg-blue-50 rounded border border-blue-200"
          >
            <h4 class="text-sm font-semibold text-zinc-800 mb-2">Related Entity</h4>
            <%= case @payment_related_entity do %>
              <% {:booking, booking} -> %>
                <div class="text-sm text-zinc-700">
                  <p><strong>Type:</strong> Booking</p>
                  <p>
                    <strong>Reference:</strong> {booking.reference_id ||
                      booking.id}
                  </p>
                  <p>
                    <strong>Check-in:</strong> {Calendar.strftime(
                      booking.checkin_date,
                      "%Y-%m-%d"
                    )}
                  </p>
                  <p>
                    <strong>Check-out:</strong> {Calendar.strftime(
                      booking.checkout_date,
                      "%Y-%m-%d"
                    )}
                  </p>
                  <p>
                    <strong>Status:</strong> {String.capitalize(
                      to_string(booking.status)
                    )}
                  </p>
                </div>
              <% {:ticket_order, ticket_order} -> %>
                <div class="text-sm text-zinc-700">
                  <p><strong>Type:</strong> Ticket Order</p>
                  <p>
                    <strong>Reference:</strong> {ticket_order.reference_id ||
                      ticket_order.id}
                  </p>
                  <%= if ticket_order.event do %>
                    <p><strong>Event:</strong> {ticket_order.event.title}</p>
                  <% end %>
                  <p>
                    <strong>Tickets:</strong> {length(ticket_order.tickets || [])}
                  </p>
                  <p>
                    <strong>Status:</strong> {String.capitalize(
                      to_string(ticket_order.status)
                    )}
                  </p>
                </div>
            <% end %>
          </div>
          <!-- Refunds Section -->
          <div class="mt-4">
            <h4 class="text-md font-semibold text-zinc-800 mb-3">
              Refunds ({length(@payment_refunds || [])})
            </h4>
            <div :if={length(@payment_refunds || []) > 0} class="overflow-x-auto">
              <table class="min-w-full divide-y divide-zinc-200 text-sm">
                <thead class="bg-zinc-50">
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Reference
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Amount
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Reason
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Status
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      QB Status
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Date
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-zinc-200">
                  <tr :for={refund <- @payment_refunds}>
                    <td class="px-4 py-2 whitespace-nowrap font-mono text-xs">
                      {refund.reference_id}
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap font-medium text-red-600">
                      {Money.to_string!(refund.amount)}
                    </td>
                    <td class="px-4 py-2 text-xs text-zinc-600 max-w-xs">
                      <div class="truncate" title={refund.reason}>
                        {refund.reason || "N/A"}
                      </div>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap">
                      <.badge type={
                        AdminBadgeHelpers.ledger_payment_status_badge_type(
                          refund.status
                        )
                      }>
                        {String.capitalize(to_string(refund.status || "unknown"))}
                      </.badge>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap">
                      <.admin_quickbooks_sync_status
                        status={refund.quickbooks_sync_status}
                        error={refund.quickbooks_sync_error}
                        error_hint={:label}
                      />
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap text-xs">
                      {format_datetime(
                        refund.inserted_at,
                        @timezone,
                        "%Y-%m-%d %H:%M"
                      )}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p
              :if={length(@payment_refunds || []) == 0}
              class="text-sm text-zinc-500 italic"
            >
              No refunds for this payment.
            </p>
          </div>
          <!-- Ledger Entries Section -->
          <div class="mt-4">
            <h4 class="text-md font-semibold text-zinc-800 mb-3">
              Ledger Entries ({length(@payment_ledger_entries || [])})
            </h4>
            <div
              :if={length(@payment_ledger_entries || []) > 0}
              class="overflow-x-auto"
            >
              <table class="min-w-full divide-y divide-zinc-200 text-sm">
                <thead class="bg-zinc-50">
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Account
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Description
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Debit/Credit
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Amount
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Date
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-zinc-200">
                  <tr :for={entry <- @payment_ledger_entries}>
                    <td class="px-4 py-2 whitespace-nowrap">
                      <div class="flex flex-col">
                        <span class="text-xs font-medium text-zinc-900">
                          {entry.account.name}
                        </span>
                        <span class="text-xs text-zinc-500">
                          {String.capitalize(to_string(entry.account.account_type))}
                        </span>
                      </div>
                    </td>
                    <td class="px-4 py-2 text-xs text-zinc-600 max-w-xs">
                      <div class="truncate" title={entry.description}>
                        {entry.description}
                      </div>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap">
                      <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_debit_credit_badge_color(entry.debit_credit)}"}>
                        {String.capitalize(to_string(entry.debit_credit))}
                      </span>
                    </td>
                    <td class={"px-4 py-2 whitespace-nowrap text-xs font-medium #{get_debit_credit_amount_color(entry.debit_credit)}"}>
                      {Money.to_string!(entry.amount)}
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap text-xs">
                      {format_datetime(
                        entry.inserted_at,
                        @timezone,
                        "%Y-%m-%d %H:%M"
                      )}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p
              :if={length(@payment_ledger_entries || []) == 0}
              class="text-sm text-zinc-500 italic"
            >
              No ledger entries for this payment.
            </p>
          </div>
        </div>

        <div class="flex justify-end gap-2">
          <.button
            type="button"
            phx-click="close_payment_modal"
            class="bg-zinc-500 hover:bg-zinc-600"
          >
            Close
          </.button>
        </div>
      </.modal>
      <!-- Expense Report Details Modal -->
      <.modal
        :if={@show_expense_report_modal && @selected_expense_report}
        id="expense-report-modal"
        show
        on_cancel={JS.push("close_expense_report_modal")}
      >
        <h3 class="text-lg font-medium text-zinc-900 mb-4">
          Expense Report Details
        </h3>

        <% totals = ExpenseReports.calculate_totals(@selected_expense_report) %>
        <!-- Basic Information -->
        <div class="mb-6 space-y-3">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            Basic Information
          </h4>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p class="font-medium text-zinc-700">Expense Report ID</p>
              <p class="text-zinc-900 font-mono text-xs">
                {String.slice(to_string(@selected_expense_report.id), 0..20)}...
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">User</p>
              <p class="text-zinc-900">
                <%= if Ecto.assoc_loaded?(@selected_expense_report.user) && @selected_expense_report.user do %>
                  <.link
                    navigate={
                      ~p"/admin/users/#{@selected_expense_report.user.id}/details"
                    }
                    class="text-blue-600 hover:underline"
                  >
                    {get_user_display_name(@selected_expense_report.user)} ({@selected_expense_report.user.email})
                  </.link>
                <% else %>
                  <span class="text-zinc-400">Unknown</span>
                <% end %>
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Purpose</p>
              <p class="text-zinc-900">{@selected_expense_report.purpose}</p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Reimbursement Method</p>
              <p class="text-zinc-900">
                {String.capitalize(
                  @selected_expense_report.reimbursement_method || "unknown"
                )}
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Status</p>
              <p class="text-zinc-900">
                <.badge type={
                  AdminBadgeHelpers.expense_report_status_badge_type(
                    @selected_expense_report.status
                  )
                }>
                  {String.capitalize(@selected_expense_report.status || "unknown")}
                </.badge>
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Certification Accepted</p>
              <p class="text-zinc-900">
                {if @selected_expense_report.certification_accepted,
                  do: "Yes",
                  else: "No"}
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Created At</p>
              <p class="text-zinc-900">
                {format_datetime(
                  @selected_expense_report.inserted_at,
                  @timezone,
                  "%Y-%m-%d %H:%M:%S"
                )}
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Updated At</p>
              <p class="text-zinc-900">
                {format_datetime(
                  @selected_expense_report.updated_at,
                  @timezone,
                  "%Y-%m-%d %H:%M:%S"
                )}
              </p>
            </div>
          </div>
        </div>
        <!-- Reimbursement Details -->
        <div class="mb-6 space-y-3">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            Reimbursement Details
          </h4>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <%= if @selected_expense_report.reimbursement_method == "check" do %>
              <div>
                <p class="font-medium text-zinc-700">Address</p>
                <p class="text-zinc-900">
                  <%= if Ecto.assoc_loaded?(@selected_expense_report.address) && @selected_expense_report.address do %>
                    {@selected_expense_report.address.address}<br />
                    {@selected_expense_report.address.city}, {@selected_expense_report.address.region} {@selected_expense_report.address.postal_code}
                  <% else %>
                    <span class="text-zinc-400">Not set</span>
                  <% end %>
                </p>
              </div>
            <% end %>
            <%= if @selected_expense_report.reimbursement_method == "bank_transfer" do %>
              <div>
                <p class="font-medium text-zinc-700">Bank Account</p>
                <p class="text-zinc-900">
                  <%= if Ecto.assoc_loaded?(@selected_expense_report.bank_account) && @selected_expense_report.bank_account do %>
                    Account ending in: {@selected_expense_report.bank_account.account_number_last_4}
                  <% else %>
                    <span class="text-zinc-400">Not set</span>
                  <% end %>
                </p>
              </div>
            <% end %>
            <%= if Ecto.assoc_loaded?(@selected_expense_report.event) && @selected_expense_report.event do %>
              <div>
                <p class="font-medium text-zinc-700">Related Event</p>
                <p class="text-zinc-900">
                  {@selected_expense_report.event.title}
                </p>
              </div>
            <% end %>
          </div>
        </div>
        <!-- QuickBooks Information -->
        <div class="mb-6 space-y-3">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            QuickBooks Information
          </h4>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p class="font-medium text-zinc-700">Sync Status</p>
              <p class="text-zinc-900">
                <.admin_quickbooks_sync_status
                  status={@selected_expense_report.quickbooks_sync_status}
                  layout={:inline}
                  default_label="unknown"
                />
              </p>
            </div>
            <%= if @selected_expense_report.quickbooks_bill_id do %>
              <div>
                <p class="font-medium text-zinc-700">QuickBooks Bill ID</p>
                <a
                  href={
                    quickbooks_entity_url(
                      "bill",
                      @selected_expense_report.quickbooks_bill_id
                    )
                  }
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-zinc-900 hover:text-blue-600 font-mono text-xs transition-colors underline decoration-dotted"
                  title="View in QuickBooks"
                >
                  {@selected_expense_report.quickbooks_bill_id}
                </a>
              </div>
            <% end %>
            <%= if @selected_expense_report.quickbooks_vendor_id do %>
              <div>
                <p class="font-medium text-zinc-700">QuickBooks Vendor ID</p>
                <p class="text-zinc-900 font-mono text-xs">
                  {@selected_expense_report.quickbooks_vendor_id}
                </p>
              </div>
            <% end %>
            <%= if @selected_expense_report.quickbooks_synced_at do %>
              <div>
                <p class="font-medium text-zinc-700">Synced At</p>
                <p class="text-zinc-900">
                  {format_datetime(
                    @selected_expense_report.quickbooks_synced_at,
                    @timezone,
                    "%Y-%m-%d %H:%M:%S"
                  )}
                </p>
              </div>
            <% end %>
            <%= if @selected_expense_report.quickbooks_last_sync_attempt_at do %>
              <div>
                <p class="font-medium text-zinc-700">Last Sync Attempt</p>
                <p class="text-zinc-900">
                  {format_datetime(
                    @selected_expense_report.quickbooks_last_sync_attempt_at,
                    @timezone,
                    "%Y-%m-%d %H:%M:%S"
                  )}
                </p>
              </div>
            <% end %>
            <%= if @selected_expense_report.quickbooks_sync_error do %>
              <div class="col-span-2">
                <p class="font-medium text-zinc-700">Sync Error</p>
                <p class="text-red-600 text-xs">
                  {format_quickbooks_sync_error(
                    @selected_expense_report.quickbooks_sync_error
                  )}
                </p>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Expense Items -->
        <div class="mb-6">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            Expense Items ({length(@selected_expense_report.expense_items || [])})
          </h4>
          <%= if Ecto.assoc_loaded?(@selected_expense_report.expense_items) && length(@selected_expense_report.expense_items) > 0 do %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-zinc-200 text-sm">
                <thead class="bg-zinc-50">
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Date
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Vendor
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Description
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Amount
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Receipt
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-zinc-200">
                  <tr :for={item <- @selected_expense_report.expense_items}>
                    <td class="px-4 py-2 whitespace-nowrap">
                      {Calendar.strftime(item.date, "%Y-%m-%d")}
                    </td>
                    <td class="px-4 py-2">{item.vendor}</td>
                    <td class="px-4 py-2 max-w-xs">
                      <div class="truncate" title={item.description}>
                        {item.description}
                      </div>
                      <%= if item.expense_type == "mileage" do %>
                        <div class="text-xs text-zinc-500 mt-0.5">
                          <%= if item.mileage_from_to do %>
                            {item.mileage_from_to} •
                          <% end %>
                          <%= if item.miles_driven do %>
                            {item.miles_driven} mi
                          <% end %>
                        </div>
                      <% end %>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap font-medium">
                      {Money.to_string!(item.amount)}
                    </td>
                    <td class="px-4 py-2">
                      <%= cond do %>
                        <% item.receipt_s3_path -> %>
                          <a
                            href={ExpenseReports.receipt_url(item.receipt_s3_path)}
                            target="_blank"
                            rel="noopener noreferrer"
                            class="text-blue-600 hover:text-blue-800 text-xs"
                          >
                            View Receipt
                          </a>
                        <% item.expense_type == "mileage" -> %>
                          <span class="text-zinc-400 text-xs">Mileage — no receipt required</span>
                        <% true -> %>
                          <span class="text-zinc-400 text-xs">No receipt</span>
                      <% end %>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% else %>
            <p class="text-sm text-zinc-500 italic">No expense items</p>
          <% end %>
        </div>
        <!-- Income Items -->
        <div class="mb-6">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            Income Items ({length(@selected_expense_report.income_items || [])})
          </h4>
          <%= if Ecto.assoc_loaded?(@selected_expense_report.income_items) && length(@selected_expense_report.income_items) > 0 do %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-zinc-200 text-sm">
                <thead class="bg-zinc-50">
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Date
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Description
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Amount
                    </th>
                    <th class="px-4 py-2 text-left text-xs font-medium text-zinc-500 uppercase">
                      Proof
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-zinc-200">
                  <tr :for={item <- @selected_expense_report.income_items}>
                    <td class="px-4 py-2 whitespace-nowrap">
                      {Calendar.strftime(item.date, "%Y-%m-%d")}
                    </td>
                    <td class="px-4 py-2 max-w-xs">
                      <div class="truncate" title={item.description}>
                        {item.description}
                      </div>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap font-medium">
                      {Money.to_string!(item.amount)}
                    </td>
                    <td class="px-4 py-2">
                      <%= if item.proof_s3_path do %>
                        <a
                          href={ExpenseReports.receipt_url(item.proof_s3_path)}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="text-blue-600 hover:text-blue-800 text-xs"
                        >
                          View Proof
                        </a>
                      <% else %>
                        <span class="text-zinc-400 text-xs">No proof</span>
                      <% end %>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% else %>
            <p class="text-sm text-zinc-500 italic">No income items</p>
          <% end %>
        </div>
        <!-- Totals -->
        <div class="mb-6 p-4 bg-zinc-50 rounded border">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">Totals</h4>
          <div class="grid grid-cols-3 gap-4 text-sm">
            <div>
              <p class="font-medium text-zinc-700">Expense Total</p>
              <p class="text-lg font-semibold text-zinc-900">
                {Money.to_string!(totals.expense_total)}
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Income Total</p>
              <p class="text-lg font-semibold text-zinc-900">
                {Money.to_string!(totals.income_total)}
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Net Total</p>
              <p class="text-lg font-semibold text-zinc-900">
                {Money.to_string!(totals.net_total)}
              </p>
            </div>
          </div>
        </div>
        <!-- Status Update Form -->
        <.form
          for={@expense_report_status_form}
          phx-submit="update_expense_report_status"
        >
          <div class="mb-4">
            <.input
              field={@expense_report_status_form[:status]}
              type="select"
              label="Update Status"
              options={[
                {"Draft", "draft"},
                {"Submitted", "submitted"},
                {"Approved", "approved"},
                {"Rejected", "rejected"},
                {"Paid", "paid"}
              ]}
              required
            />
          </div>

          <div class="flex justify-end gap-2">
            <.button
              type="button"
              phx-click="close_expense_report_modal"
              class="bg-zinc-500 hover:bg-zinc-600"
            >
              Close
            </.button>
            <.button
              type="submit"
              phx-disable-with="Updating..."
              class="bg-blue-600 hover:bg-blue-700"
            >
              Update Status
            </.button>
          </div>
        </.form>
      </.modal>
    </.side_menu>
    """
  end

  # Helper functions
  defp parse_date_to_datetime(date_string, time) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> {:ok, DateTime.new!(date, time)}
      {:error, _} -> :error
    end
  end

  # Calendar date for filter inputs/URL params (no TZ shift).
  defp format_date_param(%DateTime{} = datetime),
    do: datetime |> DateTime.to_date() |> Date.to_iso8601()

  defp format_date_param(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date_param(_), do: ""

  defp format_date_boundary(%DateTime{} = dt),
    do: DateDisplay.format_date_long(DateTime.to_date(dt), "—")

  defp format_date_boundary(_), do: "—"

  # Format DateTime in user timezone for display
  defp format_datetime(%DateTime{} = datetime, timezone, format) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime(format)
  end

  defp format_datetime(nil, _timezone, _format), do: "—"
  defp format_datetime(_, _timezone, _format), do: "—"

  defp quickbooks_entity_url(entity, txn_id) do
    qb = Application.get_env(:ysc, :quickbooks) || %{}
    base_url = to_string(qb[:url] || "")

    host =
      if String.contains?(base_url, "sandbox"),
        do: "https://app.sandbox.qbo.intuit.com",
        else: "https://app.qbo.intuit.com"

    "#{host}/app/#{entity}?txnId=#{URI.encode_www_form(to_string(txn_id))}"
  end

  defp get_payment_type_color(payment_type) do
    case payment_type do
      "Membership" -> "text-blue-600"
      "Event" -> "text-green-600"
      "Booking" -> "text-purple-600"
      "Donation" -> "text-orange-600"
      "Administration" -> "text-zinc-600"
      _ -> "text-zinc-900"
    end
  end

  defp get_user_display_name(%Ecto.Association.NotLoaded{}), do: "Unknown User"

  defp get_user_display_name(user) do
    try do
      case {user.first_name, user.last_name} do
        {nil, nil} ->
          "Unknown User"

        {first_name, nil} when is_binary(first_name) ->
          first_name

        {nil, last_name} when is_binary(last_name) ->
          last_name

        {first_name, last_name}
        when is_binary(first_name) and is_binary(last_name) ->
          "#{first_name} #{last_name}"

        _ ->
          "Unknown User"
      end
    rescue
      KeyError ->
        # User association not loaded
        "Unknown User"
    end
  end

  defp refund_changeset(_attrs, params) do
    # Include ticket_ids if present (for ticket order refunds)
    base_types = %{
      amount: :string,
      reason: :string,
      release_availability: :boolean
    }

    types =
      if Map.has_key?(params, "ticket_ids") || Map.has_key?(params, :ticket_ids) do
        Map.put(base_types, :ticket_ids, {:array, :string})
      else
        base_types
      end

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:amount, :reason])
    |> Ecto.Changeset.validate_length(:reason, min: 1, max: 1000)
    |> validate_amount()
  end

  defp credit_changeset(_attrs, params) do
    types = %{
      user_id: :string,
      amount: :string,
      reason: :string,
      entity_type: :string,
      entity_id: :string
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:amount, :reason])
    |> Ecto.Changeset.validate_length(:reason, min: 1, max: 1000)
    |> validate_amount()
  end

  defp validate_amount(changeset) do
    case Ecto.Changeset.get_field(changeset, :amount) do
      nil ->
        changeset

      amount_str ->
        case parse_amount_string(amount_str) do
          {:ok, money} ->
            if Money.positive?(money) do
              changeset
            else
              Ecto.Changeset.add_error(changeset, :amount, "must be positive")
            end

          {:error, _} ->
            Ecto.Changeset.add_error(
              changeset,
              :amount,
              "invalid amount format"
            )
        end
    end
  end

  defp get_webhook_state_color(state) do
    case state do
      :processed -> "bg-green-100 text-green-800"
      :failed -> "bg-red-100 text-red-800"
      :processing -> "bg-yellow-100 text-yellow-800"
      :pending -> "bg-blue-100 text-blue-800"
      _ -> "bg-zinc-100 text-zinc-800"
    end
  end

  # Determine balance color based on whether it's positive or negative
  # For credit-normal accounts, positive is good (green)
  # For debit-normal accounts, positive is good (green)
  # Negative balances are shown in red for both types
  defp get_balance_color(balance, _normal_balance) when is_nil(balance),
    do: "text-zinc-600"

  defp get_balance_color(balance, _normal_balance) do
    is_positive = Money.positive?(balance)
    is_zero = Money.equal?(balance, Money.new(0, :USD))

    cond do
      is_zero -> "text-zinc-600"
      is_positive -> "text-green-600"
      true -> "text-red-600"
    end
  end

  defp get_debit_credit_badge_color("debit"),
    do: "bg-purple-100 text-purple-800"

  defp get_debit_credit_badge_color("credit"), do: "bg-blue-100 text-blue-800"
  defp get_debit_credit_badge_color(:debit), do: "bg-purple-100 text-purple-800"
  defp get_debit_credit_badge_color(:credit), do: "bg-blue-100 text-blue-800"
  defp get_debit_credit_badge_color(_), do: "bg-zinc-100 text-zinc-800"

  defp get_debit_credit_amount_color("debit"), do: "text-purple-700"
  defp get_debit_credit_amount_color("credit"), do: "text-blue-700"
  defp get_debit_credit_amount_color(:debit), do: "text-purple-700"
  defp get_debit_credit_amount_color(:credit), do: "text-blue-700"
  defp get_debit_credit_amount_color(_), do: "text-zinc-900"

  defp parse_amount_string(amount_str) when is_binary(amount_str) do
    # Try parsing as decimal first
    case Decimal.parse(String.replace(amount_str, ",", "")) do
      {decimal, _} ->
        try do
          money = Money.new(decimal, :USD)
          {:ok, money}
        rescue
          _ -> {:error, :invalid_format}
        end

      :error ->
        {:error, :invalid_format}
    end
  end

  defp parse_amount_string(_), do: {:error, :invalid_format}

  # Issues the refund in Stripe first, then records it in the ledger using the
  # Stripe-issued refund id (mirrors AdminBookingsLive's process-booking-refund).
  # Ledgers.process_refund's idempotency check only matches on external_refund_id,
  # so a ledger-only refund recorded before Stripe confirms the money moved would
  # get a synthetic id that a later webhook for the real Stripe refund can't match
  # against -- producing a second Refund, a second ledger transaction, and a
  # second "your refund has been processed" email for the same payment.
  defp create_stripe_refund_and_record(payment, refund_amount, reason) do
    if payment.external_payment_id && payment.external_provider == :stripe do
      amount_cents = MoneyHelper.money_to_cents(refund_amount)

      # Deterministic per (payment, amount) so a retry after a post-refund
      # failure (e.g. Ledgers.process_refund/1 erroring) reuses the same
      # Stripe refund instead of issuing a second one. This does mean a
      # second *intentional* refund of the identical amount on the same
      # payment within Stripe's 24h idempotency window would be rejected as
      # a duplicate -- acceptable given how rare that is versus the cost of
      # a real double refund.
      idempotency_key =
        Ysc.Stripe.Idempotency.key("admin_refund_#{payment.id}_#{amount_cents}")

      case Bookings.create_stripe_refund_for_admin(
             payment.external_payment_id,
             amount_cents,
             reason,
             idempotency_key: idempotency_key
           ) do
        {:ok, stripe_refund} ->
          Ledgers.process_refund(%{
            payment_id: payment.id,
            refund_amount: refund_amount,
            reason: reason,
            external_refund_id: stripe_refund.id
          })

        {:error, stripe_reason} ->
          Ysc.Logging.error("Admin Stripe refund failed",
            payment_id: payment.id,
            amount_cents: amount_cents,
            error: inspect(stripe_reason)
          )

          {:error, {:stripe_error, stripe_reason}}
      end
    else
      {:error, :no_stripe_payment}
    end
  end

  defp expense_report_status_changeset(params) do
    types = %{
      status: :string
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:status])
    |> Ecto.Changeset.validate_inclusion(:status, [
      "draft",
      "submitted",
      "approved",
      "rejected",
      "paid"
    ])
  end

  # Helper function to release availability for a payment (booking or ticket order)
  defp release_availability_for_payment(payment_id) do
    # Find booking associated with this payment
    booking =
      from(e in Ysc.Ledgers.LedgerEntry,
        join: b in Ysc.Bookings.Booking,
        on: e.related_entity_id == b.id,
        where: e.payment_id == ^payment_id,
        where: e.related_entity_type == :booking,
        where: b.status == :complete,
        limit: 1,
        select: b
      )
      |> Repo.one()

    if booking do
      # Mark as refunded and release inventory
      case BookingLocker.refund_complete_booking(booking.id, true) do
        {:ok, _refunded_booking} ->
          Ysc.Logging.info("Booking refunded and dates released after refund",
            booking_id: booking.id,
            payment_id: payment_id
          )

          {:ok, :booking_refunded}

        {:error, reason} ->
          {:error, {:booking_refund_failed, reason}}
      end
    else
      # Try to find ticket order associated with this payment
      ticket_order =
        from(to in Ysc.Tickets.TicketOrder,
          where: to.payment_id == ^payment_id,
          where: to.status == :completed,
          limit: 1
        )
        |> Repo.one()

      if ticket_order do
        case Tickets.cancel_ticket_order(
               ticket_order,
               "Refund processed - tickets released",
               from_statuses: [:completed]
             ) do
          {:ok, _canceled_order} ->
            Ysc.Logging.info(
              "Ticket order canceled and tickets released after refund",
              ticket_order_id: ticket_order.id,
              payment_id: payment_id
            )

            {:ok, :ticket_order_canceled}

          {:error, reason} ->
            {:error, {:ticket_order_cancel_failed, reason}}
        end
      else
        {:ok, :not_found}
      end
    end
  end
end
