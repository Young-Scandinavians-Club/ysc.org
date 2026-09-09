defmodule YscWeb.AdminMoneyLive do
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.CoreComponents

  alias Ysc.Ledgers
  alias Ysc.Accounts
  alias Ysc.Webhooks
  alias Ysc.Bookings.BookingLocker
  alias Ysc.Tickets
  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.ExpenseReportItem
  alias Ysc.Repo
  alias YscWeb.AdminBadgeHelpers
  alias YscWeb.DateDisplay
  import Ecto.Query

  require Ysc.Logging

  @liquidity_account_names ["cash", "stripe_account"]
  @expense_account_names ["stripe_fees", "discount_expense"]

  @impl true
  def mount(_params, _session, socket) do
    timezone = YscWeb.TimeZone.from_connect_params(socket)

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
      |> assign(:expense_attachments, [])
      |> assign(:selected_attachment_index, 0)
      |> assign(:expense_item_flags, %{})
      |> assign(:expense_report_totals, nil)
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
    assign(
      socket,
      :expense_reports_inbox,
      ExpenseReports.list_submitted_inbox()
    )
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
          case Tickets.refund_via_stripe(
                 payment,
                 calculated_refund_amount,
                 refund_params["reason"],
                 ticket_ids: ticket_ids
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

          case Tickets.refund_via_stripe(
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
        case Tickets.calculate_refund_amount(
               ticket_order,
               refund_params["ticket_ids"]
             ) do
          {:ok, refund_amount} ->
            Map.put(refund_params, "amount", Money.to_string!(refund_amount))

          {:error, _} ->
            Map.put(refund_params, "amount", "")
        end
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
    expense_report = ExpenseReports.get_for_admin_review(expense_report_id)

    if expense_report do
      {:noreply, assign_expense_report_modal(socket, expense_report)}
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
    {:noreply, clear_expense_report_modal(socket)}
  end

  @impl true
  def handle_event(
        "update_expense_report_status",
        %{"expense_report_status" => status_params},
        socket
      ) do
    apply_expense_report_status(socket, status_params)
  end

  @impl true
  def handle_event(
        "update_expense_report_status",
        %{"status" => status},
        socket
      ) do
    apply_expense_report_status(socket, %{"status" => status})
  end

  @impl true
  def handle_event("select_expense_attachment", %{"index" => raw}, socket) do
    {:noreply, assign_selected_attachment(socket, parse_attachment_index(raw))}
  end

  @impl true
  def handle_event("expense_attachment_prev", _params, socket) do
    {:noreply, shift_attachment_index(socket, -1)}
  end

  @impl true
  def handle_event("expense_attachment_next", _params, socket) do
    {:noreply, shift_attachment_index(socket, 1)}
  end

  @impl true
  def handle_event(
        "expense_attachment_keydown",
        %{"key" => key},
        socket
      )
      when key in ["ArrowLeft", "ArrowUp"] do
    {:noreply, shift_attachment_index(socket, -1)}
  end

  @impl true
  def handle_event(
        "expense_attachment_keydown",
        %{"key" => key},
        socket
      )
      when key in ["ArrowRight", "ArrowDown"] do
    {:noreply, shift_attachment_index(socket, 1)}
  end

  @impl true
  def handle_event("expense_attachment_keydown", _params, socket) do
    {:noreply, socket}
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

    expense_reports =
      ExpenseReports.list_for_admin(start_date, end_date, page, per_page)

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
                      id={"expense-inbox-actions-stop-#{expense_report.id}"}
                      phx-hook="StopClick"
                      class="px-4 py-3 whitespace-nowrap text-right text-sm"
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
                    id={"expense-report-actions-stop-#{expense_report.id}"}
                    phx-hook="StopClick"
                    class="px-6 py-4 whitespace-nowrap text-sm font-medium text-right"
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
                    id={"webhook-actions-stop-#{webhook.id}"}
                    phx-hook="StopClick"
                    class="px-6 py-4 whitespace-nowrap text-sm font-medium text-right"
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
                <p class="font-medium text-zinc-700">
                  <%= if @selected_payout.quickbooks_transaction_type == "journal_entry" do %>
                    QuickBooks Journal Entry ID
                  <% else %>
                    QuickBooks Deposit ID
                  <% end %>
                </p>
                <a
                  href={
                    quickbooks_entity_url(
                      if(
                        @selected_payout.quickbooks_transaction_type ==
                          "journal_entry",
                        do: "journal",
                        else: "deposit"
                      ),
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

        payout_reserve_adjustment =
          @selected_payout.reserve_adjustment || Money.new(0, :USD)

        payout_computed_net =
          with {:ok, after_refunds} <-
                 Money.sub(payout_total_payments, payout_total_refunds),
               {:ok, after_fees} <- Money.sub(after_refunds, payout_fees),
               {:ok, net} <- Money.add(after_fees, payout_reserve_adjustment) do
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
            <div :if={not Money.zero?(payout_reserve_adjustment)}>
              <p class="text-zinc-600">Minimum-Balance Reserve:</p>
              <p class={[
                "font-semibold",
                if(Money.negative?(payout_reserve_adjustment),
                  do: "text-red-600",
                  else: "text-zinc-900"
                )
              ]}>
                {Money.to_string!(payout_reserve_adjustment)}
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
                Gross − Refunds − Fees
                <%= if not Money.zero?(payout_reserve_adjustment) do %>
                  + Reserve
                <% end %>
                =
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
        fullscreen
        fill_viewport
        on_cancel={JS.push("close_expense_report_modal")}
      >
        <% report = @selected_expense_report %>
        <% totals =
          @expense_report_totals || ExpenseReports.calculate_totals(report) %>
        <% {submitted_phrase, submitted_absolute} =
          submitted_label(report.inserted_at, @timezone) %>
        <% expense_rows = expense_attachment_rows(@expense_attachments) %>
        <% income_rows = income_attachment_rows(@expense_attachments) %>
        <% selected = Enum.at(@expense_attachments, @selected_attachment_index) %>
        <% attention_count = flagged_item_count(@expense_item_flags) %>
        <div
          id="expense-report-review"
          phx-hook="ExpenseReceiptKeys"
          class="flex h-full min-h-0 flex-1 flex-row overflow-hidden"
        >
          <span
            id="expense-receipt-key-left"
            class="hidden"
            phx-window-keydown="expense_attachment_prev"
            phx-key="ArrowLeft"
          ></span>
          <span
            id="expense-receipt-key-right"
            class="hidden"
            phx-window-keydown="expense_attachment_next"
            phx-key="ArrowRight"
          ></span>
          <span
            id="expense-receipt-key-up"
            class="hidden"
            phx-window-keydown="expense_attachment_prev"
            phx-key="ArrowUp"
          ></span>
          <span
            id="expense-receipt-key-down"
            class="hidden"
            phx-window-keydown="expense_attachment_next"
            phx-key="ArrowDown"
          ></span>
          <div class="flex h-full min-h-0 w-[min(34%,30rem)] min-w-[22rem] shrink-0 flex-col border-r border-zinc-200">
            <div class="min-h-0 flex-1 space-y-5 overflow-y-auto px-6 pb-6 pt-6 sm:px-8 sm:pb-8 sm:pt-8">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="min-w-0 flex-1">
                  <h3 class="text-lg font-semibold text-zinc-900">
                    {report.purpose}
                  </h3>
                  <p class="mt-1 text-sm text-zinc-600">
                    <%= if Ecto.assoc_loaded?(report.user) && report.user do %>
                      <.link
                        navigate={~p"/admin/users/#{report.user.id}/details"}
                        class="font-medium text-blue-600 hover:underline"
                      >
                        {get_user_display_name(report.user)}
                      </.link>
                      <span class="text-zinc-400">·</span>
                      <span>{report.user.email}</span>
                    <% else %>
                      <span class="text-zinc-400">Unknown member</span>
                    <% end %>
                    <span class="text-zinc-400">·</span>
                    <span title={submitted_absolute}>{submitted_phrase}</span>
                    <%= if Ecto.assoc_loaded?(report.event) && report.event do %>
                      <span class="text-zinc-400">·</span>
                      <span>Event: {report.event.title}</span>
                    <% end %>
                  </p>
                  <div class="mt-2 flex flex-wrap items-center gap-2">
                    <span
                      class="font-mono text-xs text-zinc-500"
                      title={to_string(report.id)}
                    >
                      {truncate_id(to_string(report.id))}
                    </span>
                    <.admin_clipboard_button
                      id={"copy-expense-report-id-#{report.id}"}
                      variant={:icon}
                      copy={to_string(report.id)}
                      title="Copy expense report ID"
                      aria_label="Copy expense report ID"
                    />
                  </div>
                </div>
                <div class="flex flex-col items-end gap-1">
                  <.badge type={
                    AdminBadgeHelpers.expense_report_status_badge_type(
                      report.status
                    )
                  }>
                    {String.capitalize(report.status || "unknown")}
                  </.badge>
                  <p class="text-xl font-semibold tabular-nums text-zinc-900">
                    {Money.to_string!(totals.net_total)}
                  </p>
                  <p class="text-xs text-zinc-500">Net total</p>
                  <%= if report.quickbooks_bill_id do %>
                    <a
                      id="expense-report-quickbooks-bill"
                      href={
                        quickbooks_entity_url(
                          "bill",
                          report.quickbooks_bill_id
                        )
                      }
                      target="_blank"
                      rel="noopener noreferrer"
                      class="mt-1 inline-flex items-center gap-1 text-sm font-medium text-blue-600 hover:text-blue-800 hover:underline"
                      title={report.quickbooks_bill_id}
                    >
                      View in QuickBooks
                      <.icon
                        name="hero-arrow-top-right-on-square"
                        class="h-4 w-4"
                      />
                    </a>
                  <% end %>
                </div>
              </div>

              <%= if attention_count > 0 do %>
                <p
                  id="expense-report-attention"
                  class="text-sm text-amber-800"
                >
                  {attention_count} item{if attention_count == 1,
                    do: "",
                    else: "s"} need attention
                </p>
              <% end %>

              <.line_items_table
                id="expense-report-expense-items"
                title={"Expense items (#{length(expense_rows)})"}
                rows={expense_rows}
                selected_index={@selected_attachment_index}
                flags={@expense_item_flags}
                id_prefix="expense-report-item"
                empty_copy="No expense items"
                subtotal={sum_attachment_amounts(expense_rows)}
              />

              <.line_items_table
                :if={income_rows != []}
                id="expense-report-income-items"
                title={"Income items (#{length(income_rows)})"}
                rows={income_rows}
                selected_index={@selected_attachment_index}
                flags={@expense_item_flags}
                id_prefix="income-report-item"
                empty_copy="No income items"
                subtotal={sum_attachment_amounts(income_rows)}
              />

              <details
                id="expense-report-more-details"
                class="rounded border border-zinc-200 bg-zinc-50 p-3 text-sm"
                open={not is_nil(report.quickbooks_sync_error)}
              >
                <summary class="cursor-pointer font-medium text-zinc-800">
                  More details
                </summary>
                <div class="mt-3 space-y-3">
                  <%= if report.quickbooks_sync_error do %>
                    <div
                      id="expense-report-qb-error"
                      class="rounded border border-red-200 bg-red-50 p-3 text-red-700"
                    >
                      {format_quickbooks_sync_error(report.quickbooks_sync_error)}
                    </div>
                  <% end %>
                  <div class="grid grid-cols-2 gap-3">
                    <div>
                      <p class="font-medium text-zinc-700">Certification</p>
                      <p class="text-zinc-900">
                        <%= if report.certification_accepted do %>
                          Accepted
                        <% else %>
                          <.badge type="yellow">Not accepted</.badge>
                        <% end %>
                      </p>
                    </div>
                    <div>
                      <p class="font-medium text-zinc-700">Created</p>
                      <p class="text-zinc-900">
                        {format_datetime_human(
                          report.inserted_at,
                          @timezone
                        )}
                      </p>
                    </div>
                    <div>
                      <p class="font-medium text-zinc-700">Updated</p>
                      <p class="text-zinc-900">
                        {format_datetime_human(report.updated_at, @timezone)}
                      </p>
                    </div>
                    <div>
                      <p class="font-medium text-zinc-700">
                        QuickBooks sync
                      </p>
                      <.admin_quickbooks_sync_status
                        status={report.quickbooks_sync_status}
                        layout={:inline}
                        default_label="unknown"
                      />
                    </div>
                    <%= if report.quickbooks_bill_id do %>
                      <div>
                        <p class="font-medium text-zinc-700">
                          QuickBooks Bill ID
                        </p>
                        <div class="flex items-center gap-1">
                          <a
                            href={
                              quickbooks_entity_url(
                                "bill",
                                report.quickbooks_bill_id
                              )
                            }
                            target="_blank"
                            rel="noopener noreferrer"
                            class="font-mono text-xs text-zinc-900 underline decoration-dotted hover:text-blue-600"
                            title={report.quickbooks_bill_id}
                          >
                            {truncate_id(report.quickbooks_bill_id)}
                          </a>
                          <.admin_clipboard_button
                            id={"copy-qb-bill-#{report.id}"}
                            variant={:icon}
                            copy={report.quickbooks_bill_id}
                            title="Copy QuickBooks Bill ID"
                            aria_label="Copy QuickBooks Bill ID"
                          />
                        </div>
                      </div>
                    <% end %>
                    <%= if report.quickbooks_vendor_id do %>
                      <div>
                        <p class="font-medium text-zinc-700">
                          QuickBooks Vendor ID
                        </p>
                        <div class="flex items-center gap-1">
                          <span
                            class="font-mono text-xs text-zinc-900"
                            title={report.quickbooks_vendor_id}
                          >
                            {truncate_id(report.quickbooks_vendor_id)}
                          </span>
                          <.admin_clipboard_button
                            id={"copy-qb-vendor-#{report.id}"}
                            variant={:icon}
                            copy={report.quickbooks_vendor_id}
                            title="Copy QuickBooks Vendor ID"
                            aria_label="Copy QuickBooks Vendor ID"
                          />
                        </div>
                      </div>
                    <% end %>
                    <%= if report.quickbooks_synced_at do %>
                      <div>
                        <p class="font-medium text-zinc-700">Synced at</p>
                        <p class="text-zinc-900">
                          {format_datetime_human(
                            report.quickbooks_synced_at,
                            @timezone
                          )}
                        </p>
                      </div>
                    <% end %>
                    <%= if report.quickbooks_last_sync_attempt_at do %>
                      <div>
                        <p class="font-medium text-zinc-700">
                          Last sync attempt
                        </p>
                        <p class="text-zinc-900">
                          {format_datetime_human(
                            report.quickbooks_last_sync_attempt_at,
                            @timezone
                          )}
                        </p>
                      </div>
                    <% end %>
                  </div>
                </div>
              </details>
            </div>

            <div
              id="expense-report-decision"
              class="shrink-0 border-t border-zinc-200 bg-white px-6 py-6 sm:px-8"
            >
              <p class="mb-3 text-sm text-zinc-700">
                {reimbursement_destination_summary(report, totals)}
              </p>
              <%= if report.quickbooks_bill_id do %>
                <a
                  id="expense-report-quickbooks-bill-footer"
                  href={quickbooks_entity_url("bill", report.quickbooks_bill_id)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="mb-3 inline-flex items-center gap-1 text-sm font-medium text-blue-600 hover:text-blue-800 hover:underline"
                  title={report.quickbooks_bill_id}
                >
                  View bill in QuickBooks
                  <.icon
                    name="hero-arrow-top-right-on-square"
                    class="h-4 w-4"
                  />
                </a>
              <% end %>
              <div class="flex flex-wrap items-center justify-end gap-2">
                <.button
                  type="button"
                  color="zinc"
                  variant="outline"
                  phx-click="close_expense_report_modal"
                >
                  Close
                </.button>
                <%= case report.status do %>
                  <% "submitted" -> %>
                    <.button
                      id="expense-report-reject"
                      type="button"
                      color="red"
                      phx-click="update_expense_report_status"
                      phx-value-status="rejected"
                      data-confirm="Reject this expense report?"
                    >
                      Reject
                    </.button>
                    <.button
                      id="expense-report-approve"
                      type="button"
                      color="green"
                      phx-click="update_expense_report_status"
                      phx-value-status="approved"
                    >
                      Approve
                    </.button>
                  <% "approved" -> %>
                    <.button
                      id="expense-report-revert"
                      type="button"
                      color="zinc"
                      variant="outline"
                      phx-click="update_expense_report_status"
                      phx-value-status="submitted"
                    >
                      Revert to submitted
                    </.button>
                    <.button
                      id="expense-report-mark-paid"
                      type="button"
                      color="blue"
                      phx-click="update_expense_report_status"
                      phx-value-status="paid"
                    >
                      Mark paid
                    </.button>
                  <% "rejected" -> %>
                    <.button
                      id="expense-report-reopen"
                      type="button"
                      color="blue"
                      phx-click="update_expense_report_status"
                      phx-value-status="submitted"
                    >
                      Reopen
                    </.button>
                  <% _ -> %>
                <% end %>
              </div>
              <details id="expense-report-status-form" class="mt-3">
                <summary class="cursor-pointer text-xs text-zinc-500">
                  Change status manually
                </summary>
                <.form
                  for={@expense_report_status_form}
                  phx-submit="update_expense_report_status"
                  class="mt-3"
                >
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
                  <div class="mt-2 flex justify-end">
                    <.button type="submit" phx-disable-with="Updating...">
                      Update Status
                    </.button>
                  </div>
                </.form>
              </details>
            </div>
          </div>

          <div
            id="expense-receipt-viewer"
            class="flex h-full min-h-0 min-w-0 flex-1 flex-col px-6 pb-6 pt-6 sm:px-8 sm:pb-8 sm:pt-8"
          >
            <%= if selected do %>
              <div class="mb-3 flex flex-wrap items-start justify-between gap-3 pr-12">
                <div class="min-w-0">
                  <p
                    id="expense-receipt-caption"
                    class="font-medium text-zinc-900"
                  >
                    {selected.label}
                  </p>
                  <p class="text-sm text-zinc-600">
                    {format_item_date(selected.date)}
                    <span class="text-zinc-400">·</span>
                    <span class="tabular-nums">
                      {Money.to_string!(selected.amount)}
                    </span>
                    <%= if selected.filename do %>
                      <span class="text-zinc-400">·</span>
                      <span class="font-mono text-xs">{selected.filename}</span>
                    <% end %>
                  </p>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs tabular-nums text-zinc-500">
                    {selected.index + 1} of {length(@expense_attachments)}
                  </span>
                  <.button
                    id="expense-receipt-prev"
                    type="button"
                    color="zinc"
                    variant="outline"
                    phx-click="expense_attachment_prev"
                    class="!min-h-0 px-2 py-1"
                  >
                    <.icon name="hero-chevron-left" class="h-4 w-4" />
                    <span class="sr-only">Previous item</span>
                  </.button>
                  <.button
                    id="expense-receipt-next"
                    type="button"
                    color="zinc"
                    variant="outline"
                    phx-click="expense_attachment_next"
                    class="!min-h-0 px-2 py-1"
                  >
                    <.icon name="hero-chevron-right" class="h-4 w-4" />
                    <span class="sr-only">Next item</span>
                  </.button>
                  <%= if attachment_open_url(selected) do %>
                    <a
                      id="expense-receipt-open"
                      href={attachment_open_url(selected)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-xs font-medium text-blue-600 hover:underline"
                    >
                      Open in new tab
                    </a>
                  <% end %>
                </div>
              </div>
              <div class="relative min-h-0 flex-1 overflow-hidden rounded bg-zinc-100">
                <%= cond do %>
                  <% selected.media == :image && selected.url -> %>
                    <div
                      id={"expense-receipt-lightbox-#{selected.index}"}
                      phx-hook="ReceiptLightbox"
                      class="absolute inset-0 flex items-center justify-center p-3"
                    >
                      <a
                        href={selected.url}
                        data-lightbox="receipt"
                        class="flex h-full max-h-full w-full cursor-zoom-in items-center justify-center"
                      >
                        <img
                          src={selected.url}
                          alt={"Receipt for #{selected.label}"}
                          class="max-h-full max-w-full object-contain"
                        />
                      </a>
                    </div>
                  <% selected.media == :pdf && selected.preview_url -> %>
                    <iframe
                      id={"expense-receipt-pdf-#{selected.index}"}
                      src={selected.preview_url}
                      title={"Receipt for #{selected.label}"}
                      tabindex="-1"
                      class="absolute inset-0 h-full w-full border-0"
                    ></iframe>
                  <% selected.expense_type == "mileage" -> %>
                    <p class="flex h-full items-center justify-center p-6 text-center text-sm text-zinc-500">
                      Mileage — no receipt required
                    </p>
                  <% selected.kind == :income -> %>
                    <p class="flex h-full items-center justify-center p-6 text-center text-sm text-zinc-500">
                      No proof attached
                    </p>
                  <% true -> %>
                    <p class="flex h-full items-center justify-center p-6 text-center text-sm text-zinc-500">
                      No receipt attached
                    </p>
                <% end %>
              </div>
            <% else %>
              <p class="p-6 text-center text-sm text-zinc-500">
                No expense items
              </p>
            <% end %>
          </div>
        </div>
      </.modal>
    </.side_menu>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :selected_index, :integer, required: true
  attr :flags, :map, required: true
  attr :id_prefix, :string, required: true
  attr :empty_copy, :string, required: true
  attr :subtotal, :any, required: true

  defp line_items_table(assigns) do
    ~H"""
    <div id={@id}>
      <h4 class="mb-2 text-sm font-semibold text-zinc-800">{@title}</h4>
      <%= if @rows == [] do %>
        <p class="text-sm italic text-zinc-500">{@empty_copy}</p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-zinc-200 text-sm">
            <thead class="bg-zinc-50">
              <tr>
                <th class="px-2 py-2 text-left text-xs font-medium uppercase text-zinc-500">
                  #
                </th>
                <th class="px-2 py-2 text-left text-xs font-medium uppercase text-zinc-500">
                  Date
                </th>
                <th class="px-2 py-2 text-left text-xs font-medium uppercase text-zinc-500">
                  Vendor
                </th>
                <th class="px-2 py-2 text-left text-xs font-medium uppercase text-zinc-500">
                  Description
                </th>
                <th class="px-2 py-2 text-right text-xs font-medium uppercase text-zinc-500">
                  Amount
                </th>
                <th class="px-2 py-2 text-left text-xs font-medium uppercase text-zinc-500">
                  Receipt
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-200 bg-white">
              <tr
                :for={row <- @rows}
                id={"#{@id_prefix}-#{row.item_id}"}
                phx-click="select_expense_attachment"
                phx-value-index={row.index}
                aria-selected={@selected_index == row.index}
                class={[
                  "cursor-pointer hover:bg-zinc-50",
                  @selected_index == row.index &&
                    "bg-blue-50 ring-1 ring-inset ring-blue-200"
                ]}
              >
                <td class="px-2 py-2 tabular-nums text-zinc-500">
                  {row.index + 1}
                </td>
                <td class="whitespace-nowrap px-2 py-2">
                  {format_item_date(row.date)}
                </td>
                <td class="px-2 py-2">{row.vendor || "—"}</td>
                <td class="max-w-xs px-2 py-2">
                  <div>{row.description}</div>
                  <%= if row.expense_type == "mileage" do %>
                    <div
                      id={"#{@id_prefix}-#{row.item_id}-mileage"}
                      class="mt-0.5 text-xs text-zinc-500"
                    >
                      <%= if row.mileage_from_to do %>
                        {row.mileage_from_to} •
                      <% end %>
                      <%= if row.miles_driven do %>
                        {row.miles_driven} mi × {Money.to_string!(
                          ExpenseReportItem.mileage_rate()
                        )}
                      <% end %>
                    </div>
                  <% end %>
                  <%= if Map.get(@flags, row.item_id, []) != [] do %>
                    <div
                      id={"#{@id_prefix}-#{row.item_id}-flags"}
                      class="mt-1 flex flex-wrap gap-1"
                    >
                      <.badge
                        :for={flag <- Map.get(@flags, row.item_id, [])}
                        type="yellow"
                      >
                        {flag_label(flag)}
                      </.badge>
                    </div>
                  <% end %>
                </td>
                <td
                  id={"#{@id_prefix}-#{row.item_id}-amount"}
                  class="whitespace-nowrap px-2 py-2 text-right font-medium tabular-nums"
                >
                  {Money.to_string!(row.amount)}
                </td>
                <td
                  id={"#{@id_prefix}-#{row.item_id}-receipt"}
                  class="px-2 py-2"
                >
                  <span class="sr-only">{receipt_cell_label(row)}</span>
                  <%= cond do %>
                    <% row.media == :image && row.url -> %>
                      <img
                        src={row.url}
                        alt={receipt_cell_label(row)}
                        title={receipt_cell_label(row)}
                        class="h-10 w-10 rounded object-cover"
                      />
                    <% row.media == :pdf -> %>
                      <.icon
                        name="hero-document-text"
                        class="h-8 w-8 text-red-600"
                      />
                    <% true -> %>
                      <span
                        title={receipt_cell_label(row)}
                        class="inline-block h-8 w-8 rounded border border-dashed border-zinc-300"
                      ></span>
                  <% end %>
                </td>
              </tr>
            </tbody>
            <tfoot>
              <tr class="bg-zinc-50">
                <td
                  colspan="4"
                  class="px-2 py-2 text-right text-xs font-medium uppercase text-zinc-500"
                >
                  Subtotal
                </td>
                <td class="px-2 py-2 text-right font-semibold tabular-nums">
                  {Money.to_string!(@subtotal)}
                </td>
                <td></td>
              </tr>
            </tfoot>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp apply_expense_report_status(socket, status_params) do
    expense_report = socket.assigns.selected_expense_report

    expense_report =
      if expense_report do
        ExpenseReports.get_for_admin_review(expense_report.id)
      end

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
           |> clear_expense_report_modal()
           |> load_expense_reports_inbox()
           |> maybe_refresh_expense_reports_list()}

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
       |> clear_expense_report_modal()}
    end
  end

  defp assign_expense_report_modal(socket, expense_report) do
    attachments = build_expense_attachments(expense_report)
    flags = compute_item_flags(expense_report)

    status_form =
      %{status: expense_report.status}
      |> expense_report_status_changeset()
      |> to_form(as: :expense_report_status)

    socket
    |> assign(:show_expense_report_modal, true)
    |> assign(:selected_expense_report, expense_report)
    |> assign(:expense_attachments, attachments)
    |> assign(:selected_attachment_index, default_attachment_index(attachments))
    |> assign(:expense_item_flags, flags)
    |> assign(
      :expense_report_totals,
      ExpenseReports.calculate_totals(expense_report)
    )
    |> assign(:expense_report_status_form, status_form)
  end

  defp clear_expense_report_modal(socket) do
    socket
    |> assign(:show_expense_report_modal, false)
    |> assign(:selected_expense_report, nil)
    |> assign(:expense_attachments, [])
    |> assign(:selected_attachment_index, 0)
    |> assign(:expense_item_flags, %{})
    |> assign(:expense_report_totals, nil)
    |> assign(
      :expense_report_status_form,
      to_form(%{}, as: :expense_report_status)
    )
  end

  defp parse_attachment_index(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {index, ""} -> index
      _ -> nil
    end
  end

  defp parse_attachment_index(raw) when is_integer(raw), do: raw
  defp parse_attachment_index(_), do: nil

  defp assign_selected_attachment(socket, nil), do: socket

  defp assign_selected_attachment(socket, index) when is_integer(index) do
    max_index = length(socket.assigns.expense_attachments) - 1

    if max_index < 0 do
      socket
    else
      assign(socket, :selected_attachment_index, min(max(index, 0), max_index))
    end
  end

  defp shift_attachment_index(socket, delta) do
    attachments = socket.assigns.expense_attachments
    count = length(attachments)

    if count == 0 do
      socket
    else
      current = socket.assigns.selected_attachment_index || 0

      assign(
        socket,
        :selected_attachment_index,
        Integer.mod(current + delta, count)
      )
    end
  end

  defp default_attachment_index(attachments) do
    case Enum.find_index(attachments, &(&1.media != :none)) do
      nil -> 0
      index -> index
    end
  end

  defp ordered_report_items(items) when is_list(items) do
    Enum.sort_by(items, &{&1.position || 999_999, &1.id})
  end

  defp ordered_report_items(_), do: []

  defp build_expense_attachments(expense_report) do
    expense_rows =
      expense_report.expense_items
      |> ordered_report_items()
      |> Enum.map(&expense_item_to_attachment/1)

    income_rows =
      expense_report.income_items
      |> ordered_report_items()
      |> Enum.map(&income_item_to_attachment/1)

    (expense_rows ++ income_rows)
    |> Enum.with_index()
    |> Enum.map(fn {row, index} -> Map.put(row, :index, index) end)
  end

  defp expense_item_to_attachment(item) do
    s3_path = blank_to_nil(item.receipt_s3_path)
    media = ExpenseReports.media_type_for_path(s3_path)

    %{
      kind: :expense,
      item_id: item.id,
      label: item.vendor || item.description || "Expense item",
      vendor: item.vendor,
      description: item.description,
      date: item.date,
      amount: item.amount,
      s3_path: s3_path,
      filename: s3_path && Path.basename(s3_path),
      media: media,
      url: s3_path && ExpenseReports.receipt_url(s3_path),
      preview_url: s3_path && ExpenseReports.receipt_preview_url(s3_path),
      expense_type: item.expense_type,
      mileage_from_to: item.mileage_from_to,
      miles_driven: item.miles_driven
    }
  end

  defp income_item_to_attachment(item) do
    s3_path = blank_to_nil(item.proof_s3_path)
    media = ExpenseReports.media_type_for_path(s3_path)

    %{
      kind: :income,
      item_id: item.id,
      label: item.description || "Income item",
      vendor: nil,
      description: item.description,
      date: item.date,
      amount: item.amount,
      s3_path: s3_path,
      filename: s3_path && Path.basename(s3_path),
      media: media,
      url: s3_path && ExpenseReports.receipt_url(s3_path),
      preview_url: s3_path && ExpenseReports.receipt_preview_url(s3_path),
      expense_type: nil,
      mileage_from_to: nil,
      miles_driven: nil
    }
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  defp compute_item_flags(expense_report) do
    today = Date.utc_today()
    inserted_date = DateTime.to_date(expense_report.inserted_at)
    stale_cutoff = Date.add(inserted_date, -90)
    items = ordered_report_items(expense_report.expense_items)

    duplicate_keys =
      items
      |> Enum.frequencies_by(&duplicate_item_key/1)
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> MapSet.new(fn {key, _count} -> key end)

    Map.new(items, fn item ->
      flags =
        []
        |> maybe_flag(
          item.expense_type != "mileage" and
            is_nil(blank_to_nil(item.receipt_s3_path)),
          :missing_receipt
        )
        |> maybe_flag(
          item.date && Date.compare(item.date, today) == :gt,
          :future_date
        )
        |> maybe_flag(
          item.date && Date.compare(item.date, stale_cutoff) == :lt,
          :stale_date
        )
        |> maybe_flag(
          MapSet.member?(duplicate_keys, duplicate_item_key(item)),
          :possible_duplicate
        )

      {item.id, flags}
    end)
  end

  defp maybe_flag(flags, true, flag), do: flags ++ [flag]
  defp maybe_flag(flags, _false, _flag), do: flags

  defp duplicate_item_key(item) do
    {item.vendor, money_flag_key(item.amount), item.date}
  end

  defp money_flag_key(%Money{} = money), do: {money.currency, money.amount}
  defp money_flag_key(other), do: other

  defp flag_label(:missing_receipt), do: "Missing receipt"
  defp flag_label(:future_date), do: "Future date"
  defp flag_label(:stale_date), do: "Older than 90 days"
  defp flag_label(:possible_duplicate), do: "Possible duplicate"

  defp flag_label(other),
    do: other |> to_string() |> String.replace("_", " ")

  defp flagged_item_count(flags) when is_map(flags) do
    flags
    |> Map.values()
    |> Enum.count(&(&1 != []))
  end

  defp flagged_item_count(_), do: 0

  defp truncate_id(value) when is_binary(value) do
    if String.length(value) <= 10 do
      value
    else
      String.slice(value, 0, 6) <> "…" <> String.slice(value, -4, 4)
    end
  end

  defp truncate_id(value) when not is_nil(value),
    do: truncate_id(to_string(value))

  defp truncate_id(_), do: ""

  defp format_datetime_human(%DateTime{} = datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %-d, %Y, %-I:%M %p")
  end

  defp format_datetime_human(_, _), do: "—"

  defp format_item_date(%Date{} = date),
    do: Calendar.strftime(date, "%b %-d, %Y")

  defp format_item_date(_), do: "—"

  defp submitted_label(%DateTime{} = dt, timezone) do
    now = DateTime.now!(timezone)
    local = DateTime.shift_zone!(dt, timezone)
    days = Date.diff(DateTime.to_date(now), DateTime.to_date(local))
    absolute = Calendar.strftime(local, "%b %-d, %Y")

    phrase =
      cond do
        days <= 0 -> "Submitted today"
        days == 1 -> "Submitted 1 day ago"
        true -> "Submitted #{days} days ago"
      end

    {phrase, absolute}
  end

  defp submitted_label(_, _), do: {"Submitted", nil}

  defp reimbursement_destination_summary(report, totals) do
    amount = Money.to_string!(totals.net_total)

    verb =
      if Money.negative?(totals.net_total) do
        "Member owes"
      else
        "Reimburse"
      end

    destination =
      case report.reimbursement_method do
        "check" ->
          if Ecto.assoc_loaded?(report.address) && report.address do
            address = report.address

            "via check to #{address.address}, #{address.city} #{address.region}"
          else
            "via check"
          end

        "bank_transfer" ->
          if Ecto.assoc_loaded?(report.bank_account) && report.bank_account do
            "via bank transfer to account ending #{report.bank_account.account_number_last_4}"
          else
            "via bank transfer"
          end

        nil ->
          "Method not set"

        other ->
          "via #{other}"
      end

    "#{verb} #{amount} #{destination}"
  end

  defp attachment_open_url(%{media: :pdf, preview_url: url})
       when is_binary(url),
       do: url

  defp attachment_open_url(%{url: url}) when is_binary(url), do: url
  defp attachment_open_url(_), do: nil

  defp receipt_cell_label(row) do
    cond do
      row.media == :image -> "Image"
      row.media == :pdf -> "PDF"
      row.kind == :income && is_nil(row.s3_path) -> "No proof"
      row.expense_type == "mileage" -> "Mileage — no receipt required"
      true -> "No receipt"
    end
  end

  defp expense_attachment_rows(attachments),
    do: Enum.filter(attachments, &(&1.kind == :expense))

  defp income_attachment_rows(attachments),
    do: Enum.filter(attachments, &(&1.kind == :income))

  defp sum_attachment_amounts(rows) do
    Enum.reduce(rows, Money.new(0, :USD), fn row, acc ->
      case row.amount do
        %Money{} = money ->
          case Money.add(acc, money) do
            {:ok, sum} -> sum
            _ -> acc
          end

        _ ->
          acc
      end
    end)
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
