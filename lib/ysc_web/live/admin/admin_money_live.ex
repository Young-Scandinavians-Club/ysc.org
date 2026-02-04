defmodule YscWeb.AdminMoneyLive do
  use Phoenix.LiveView,
    layout: {YscWeb.Layouts, :admin_app}

  import YscWeb.CoreComponents

  use Phoenix.VerifiedRoutes,
    endpoint: YscWeb.Endpoint,
    router: YscWeb.Router,
    statics: YscWeb.static_paths()

  alias Ysc.Ledgers
  alias Ysc.Accounts
  alias Ysc.Webhooks
  alias Ysc.Bookings.BookingLocker
  alias Ysc.Tickets
  alias Ysc.ExpenseReports
  alias Ysc.ExpenseReports.ExpenseReport
  alias Ysc.Repo
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    # Set default date range to current calendar year
    current_year = DateTime.utc_now().year
    start_date = DateTime.new!(Date.new!(current_year, 1, 1), ~T[00:00:00])
    end_date = DateTime.new!(Date.new!(current_year, 12, 31), ~T[23:59:59])

    # Initialize socket with placeholder values for fast initial render
    socket =
      socket
      |> assign(:page_title, "Money")
      |> assign(:active_page, :money)
      |> assign(:loading_money_data, true)
      # Placeholder values - will be populated when connected
      |> assign(:accounts_with_balances, [])
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
      |> assign(:sections_collapsed, %{
        accounts: false,
        quick_actions: false,
        payments: false,
        ledger_entries: true,
        webhooks: true,
        expense_reports: true
      })
      |> assign(:sections_loaded, %{
        accounts: false,
        quick_actions: false,
        payments: false,
        ledger_entries: false,
        webhooks: false,
        expense_reports: false
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
      # Placeholder values for paginated data
      |> assign(:recent_payments, [])
      |> assign(:payments_end?, true)
      |> assign(:ledger_entries, [])
      |> assign(:ledger_entries_end?, true)
      |> assign(:webhook_events, [])
      |> assign(:webhooks_end?, true)
      |> assign(:expense_reports, [])
      |> assign(:expense_reports_end?, true)

    # Schedule data loading only when connected (stateful mount)
    if connected?(socket) do
      send(self(), :load_money_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_money_data, socket) do
    start_date = socket.assigns.start_date
    end_date = socket.assigns.end_date

    accounts_with_balances =
      Ledgers.get_accounts_with_balances(start_date, end_date)

    ledger_accounts = Ledgers.list_accounts()

    sections_loaded = Map.put(socket.assigns.sections_loaded, :accounts, true)

    socket =
      socket
      |> assign(:loading_money_data, false)
      |> assign(:accounts_with_balances, accounts_with_balances)
      |> assign(:ledger_accounts, ledger_accounts)
      |> assign(:sections_loaded, sections_loaded)

    # Only load data for sections that start expanded (payments)
    # Collapsed sections (ledger_entries, webhooks, expense_reports) will load on demand
    socket =
      if socket.assigns.sections_collapsed[:payments] do
        socket
      else
        updated_sections_loaded = Map.put(sections_loaded, :payments, true)

        socket
        |> paginate_payments(1)
        |> assign(:sections_loaded, updated_sections_loaded)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Preserve date range from params if provided
    socket =
      if params["start_date"] && params["end_date"] do
        try do
          start_date =
            parse_date_to_datetime(params["start_date"], ~T[00:00:00])

          end_date = parse_date_to_datetime(params["end_date"], ~T[23:59:59])

          socket
          |> assign(:start_date, start_date)
          |> assign(:end_date, end_date)
        rescue
          _ -> socket
        end
      else
        socket
      end

    # Ensure live_action is set
    socket = assign(socket, :live_action, socket.assigns.live_action || :index)

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
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
      |> put_flash(:error, "Payment not found")
      |> push_navigate(to: build_money_path(socket))
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
      |> put_flash(:error, "Payment not found")
      |> push_navigate(to: build_money_path(socket))
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
      |> put_flash(:error, "Payout not found")
      |> push_navigate(to: build_money_path(socket))
    end
  end

  defp apply_action(socket, _action, _params) do
    socket
  end

  # Helper to build money path with date range preserved
  defp build_money_path(socket, sub_path \\ "") do
    base_path = ~p"/admin/money"

    full_path =
      if sub_path != "", do: "#{base_path}#{sub_path}", else: base_path

    query_params =
      if socket.assigns[:start_date] && socket.assigns[:end_date] do
        %{
          "start_date" =>
            Calendar.strftime(socket.assigns.start_date, "%Y-%m-%d"),
          "end_date" => Calendar.strftime(socket.assigns.end_date, "%Y-%m-%d")
        }
      else
        %{}
      end

    if map_size(query_params) > 0 do
      "#{full_path}?#{URI.encode_query(query_params)}"
    else
      full_path
    end
  end

  @impl true
  def handle_event("show_refund_modal", %{"payment_id" => payment_id}, socket) do
    path = build_money_path(socket, "/payments/#{payment_id}/refund")
    {:noreply, push_navigate(socket, to: path)}
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
    {:noreply, push_navigate(socket, to: build_money_path(socket))}
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
      {:noreply, push_navigate(socket, to: path)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Payout not found for this payment")}
    end
  end

  @impl true
  def handle_event("close_payout_modal", _params, socket) do
    {:noreply, push_navigate(socket, to: build_money_path(socket))}
  end

  @impl true
  def handle_event("show_payment_modal", %{"payment_id" => payment_id}, socket) do
    path = build_money_path(socket, "/payments/#{payment_id}")
    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def handle_event("close_payment_modal", _params, socket) do
    {:noreply, push_navigate(socket, to: build_money_path(socket))}
  end

  @impl true
  def handle_event("process_refund", %{"refund" => refund_params}, socket) do
    %{selected_payment: payment, ticket_order: ticket_order} = socket.assigns

    # Check if this is a partial ticket refund
    ticket_ids =
      if refund_params["ticket_ids"], do: refund_params["ticket_ids"], else: []

    # If ticket IDs are provided, refund individual tickets
    if ticket_order && ticket_ids != [] do
      case Tickets.refund_tickets(
             ticket_order,
             ticket_ids,
             refund_params["reason"]
           ) do
        {:ok, %{refund_amount: calculated_refund_amount}} ->
          # Process the ledger refund with the calculated amount
          refund_attrs = %{
            payment_id: payment.id,
            refund_amount: calculated_refund_amount,
            reason: refund_params["reason"],
            external_refund_id: "admin_refund_#{Ecto.ULID.generate()}"
          }

          case Ledgers.process_refund(refund_attrs) do
            {:ok, {_refund, _transaction, _entries}} ->
              # Refresh data
              %{start_date: start_date, end_date: end_date} = socket.assigns

              accounts_with_balances =
                Ledgers.get_accounts_with_balances(start_date, end_date)

              # Navigate to payment details view to show the refund
              payment_path = build_money_path(socket, "/payments/#{payment.id}")

              {:noreply,
               socket
               |> put_flash(
                 :info,
                 "Refunded #{length(ticket_ids)} ticket(s) successfully. Amount: #{Money.to_string!(calculated_refund_amount)}"
               )
               |> assign(:accounts_with_balances, accounts_with_balances)
               |> assign(:payments_page, 1)
               |> assign(:ledger_entries_page, 1)
               |> assign(:webhooks_page, 1)
               |> paginate_payments(1)
               |> paginate_ledger_entries(1)
               |> paginate_webhooks(1)
               |> push_navigate(to: payment_path)}

            {:error, _changeset} ->
              {:noreply,
               socket
               |> put_flash(:error, "Failed to process refund in ledger")}
          end

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to refund tickets: #{inspect(reason)}")}
      end
    else
      # Full refund (existing logic)
      case parse_amount_string(refund_params["amount"]) do
        {:ok, refund_amount} ->
          refund_attrs = %{
            payment_id: payment.id,
            refund_amount: refund_amount,
            reason: refund_params["reason"],
            external_refund_id: "admin_refund_#{Ecto.ULID.generate()}"
          }

          # Check if we should release availability
          release_availability = refund_params["release_availability"] == "true"

          case Ledgers.process_refund(refund_attrs) do
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
                    require Logger

                    Logger.warning(
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
               |> put_flash(:info, flash_message)
               |> assign(:accounts_with_balances, accounts_with_balances)
               |> assign(:payments_page, 1)
               |> assign(:ledger_entries_page, 1)
               |> assign(:webhooks_page, 1)
               |> paginate_payments(1)
               |> paginate_ledger_entries(1)
               |> paginate_webhooks(1)
               |> push_navigate(to: payment_path)}

            {:error, _changeset} ->
              {:noreply,
               socket
               |> put_flash(:error, "Failed to process refund")}
          end

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Invalid amount format")}
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
             |> put_flash(:info, "Credit added successfully")
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
             |> put_flash(:error, "Failed to add credit")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid amount format")}
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
                    case Money.div(
                           ticket_order.total_amount,
                           donation_tickets_count
                         ) do
                      {:ok, ticket_amount} ->
                        case Money.add(acc, ticket_amount) do
                          {:ok, new_total} -> new_total
                          {:error, _} -> acc
                        end

                      {:error, _} ->
                        acc
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
  def handle_event("toggle_section", %{"section" => section}, socket) do
    section_atom = String.to_existing_atom(section)
    current_state = socket.assigns.sections_collapsed[section_atom]
    is_expanding = current_state == true
    was_loaded = socket.assigns.sections_loaded[section_atom]

    updated_sections =
      Map.update!(socket.assigns.sections_collapsed, section_atom, fn _ ->
        !current_state
      end)

    socket =
      socket
      |> assign(:sections_collapsed, updated_sections)

    # Load data when expanding a section for the first time
    socket =
      if is_expanding and not was_loaded do
        sections_loaded =
          Map.put(socket.assigns.sections_loaded, section_atom, true)

        socket
        |> load_section_data(section_atom)
        |> assign(:sections_loaded, sections_loaded)
      else
        socket
      end

    {:noreply, socket}
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
       |> put_flash(:error, "Expense report not found")}
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
           |> put_flash(:info, "Expense report status updated successfully")
           |> assign(:show_expense_report_modal, false)
           |> assign(:selected_expense_report, nil)
           |> assign(:expense_reports_page, 1)
           |> paginate_expense_reports(1)
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
           |> put_flash(:error, error_message)
           |> assign(
             :expense_report_status_form,
             to_form(changeset, as: :expense_report_status)
           )}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Expense report not found")
       |> assign(:show_expense_report_modal, false)
       |> assign(:selected_expense_report, nil)}
    end
  end

  @impl true
  def handle_event(
        "update_date_range",
        %{"start_date" => start_date_str, "end_date" => end_date_str},
        socket
      ) do
    # Parse the date strings and convert to DateTime
    start_date = parse_date_to_datetime(start_date_str, ~T[00:00:00])
    end_date = parse_date_to_datetime(end_date_str, ~T[23:59:59])

    # Get updated data with new date range
    accounts_with_balances =
      Ledgers.get_accounts_with_balances(start_date, end_date)

    {:noreply,
     socket
     |> assign(:accounts_with_balances, accounts_with_balances)
     |> assign(:start_date, start_date)
     |> assign(:end_date, end_date)
     |> assign(:payments_page, 1)
     |> assign(:ledger_entries_page, 1)
     |> assign(:webhooks_page, 1)
     |> assign(:expense_reports_page, 1)
     |> paginate_payments(1)
     |> paginate_ledger_entries(1)
     |> paginate_webhooks(1)
     |> paginate_expense_reports(1)}
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
    |> assign(:recent_payments, recent_payments)
    |> assign(:payments_page, page)
    |> assign(:payments_end?, length(recent_payments) < per_page)
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

  defp load_section_data(socket, :ledger_entries) do
    paginate_ledger_entries(socket, 1)
  end

  defp load_section_data(socket, :webhooks) do
    paginate_webhooks(socket, 1)
  end

  defp load_section_data(socket, :expense_reports) do
    paginate_expense_reports(socket, 1)
  end

  defp load_section_data(socket, :payments) do
    paginate_payments(socket, 1)
  end

  defp load_section_data(socket, _section) do
    socket
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
    >
      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Money Management
        </h1>
      </div>
      <!-- Date Range Filter -->
      <div class="mb-6 bg-white p-4 rounded border">
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Date Range Filter</h3>
        <form phx-submit="update_date_range" class="flex gap-4 items-end">
          <div>
            <label
              for="start_date"
              class="block text-sm font-medium text-zinc-700 mb-1"
            >
              Start Date
            </label>
            <input
              type="date"
              id="start_date"
              name="start_date"
              value={Calendar.strftime(@start_date, "%Y-%m-%d")}
              class="block w-full rounded-md border-zinc-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            />
          </div>
          <div>
            <label
              for="end_date"
              class="block text-sm font-medium text-zinc-700 mb-1"
            >
              End Date
            </label>
            <input
              type="date"
              id="end_date"
              name="end_date"
              value={Calendar.strftime(@end_date, "%Y-%m-%d")}
              class="block w-full rounded-md border-zinc-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            />
          </div>
          <.button
            type="submit"
            phx-disable-with="Updating..."
            class="bg-blue-600 hover:bg-blue-700"
          >
            Update
          </.button>
        </form>
        <p class="text-sm text-zinc-600 mt-2">
          Showing data from <%= Calendar.strftime(@start_date, "%B %d, %Y") %> to <%= Calendar.strftime(
            @end_date,
            "%B %d, %Y"
          ) %>
        </p>
      </div>
      <!-- Account Balances -->
      <div class="mb-8 bg-white rounded border">
        <button
          phx-click="toggle_section"
          phx-value-section="accounts"
          class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
        >
          <h2 class="text-xl font-semibold text-zinc-800">Account Balances</h2>
          <.icon
            name={
              if @sections_collapsed.accounts,
                do: "hero-chevron-right",
                else: "hero-chevron-down"
            }
            class="w-5 h-5 text-zinc-600"
          />
        </button>
        <div :if={!@sections_collapsed.accounts} class="p-4 pt-0">
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <div
              :for={account_data <- @accounts_with_balances}
              class="bg-white p-4 rounded border"
            >
              <div class="flex justify-between items-start mb-2">
                <h3 class="font-medium text-zinc-900">
                  <%= account_data.account.name %>
                </h3>
                <span class={"px-2 py-1 text-xs font-semibold rounded #{get_normal_balance_badge_color(account_data.account.normal_balance)}"}>
                  <%= String.capitalize(
                    to_string(account_data.account.normal_balance || "debit")
                  ) %>-normal
                </span>
              </div>
              <p class="text-sm text-zinc-600 mb-2">
                <%= account_data.account.description %>
              </p>
              <p class={"text-lg font-semibold mt-2 #{get_balance_color(account_data.balance, account_data.account.normal_balance)}"}>
                <%= Money.to_string!(account_data.balance || Money.new(0, :USD)) %>
              </p>
              <p class="text-xs text-zinc-500 capitalize mt-1">
                <%= account_data.account.account_type %>
              </p>
            </div>
          </div>
        </div>
      </div>
      <!-- Recent Payments -->
      <div class="mb-8 bg-white rounded border">
        <button
          phx-click="toggle_section"
          phx-value-section="payments"
          class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
        >
          <h2 class="text-xl font-semibold text-zinc-800">Recent Payments</h2>
          <.icon
            name={
              if @sections_collapsed.payments,
                do: "hero-chevron-right",
                else: "hero-chevron-down"
            }
            class="w-5 h-5 text-zinc-600"
          />
        </button>
        <div :if={!@sections_collapsed.payments} class="overflow-hidden">
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
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Amount
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Status
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Date
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr :for={payment <- @recent_payments}>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-zinc-900">
                  <%= payment.reference_id %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <div class="flex flex-col">
                    <span class="font-medium text-zinc-900">
                      <%= if Ecto.assoc_loaded?(payment.user) && payment.user do
                        get_user_display_name(payment.user)
                      else
                        "System Transaction"
                      end %>
                    </span>
                    <span class="text-xs text-zinc-500">
                      <%= if Ecto.assoc_loaded?(payment.user) && payment.user do
                        payment.user.email
                      else
                        "System Transaction"
                      end %>
                    </span>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <div class="flex flex-col">
                    <span class={"font-medium #{get_payment_type_color(payment.payment_type_info.type)}"}>
                      <%= payment.payment_type_info.type %>
                    </span>
                    <span class="text-xs text-zinc-500">
                      <%= payment.payment_type_info.details %>
                    </span>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <%= Money.to_string!(payment.amount) %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{if payment.status == :completed, do: "bg-green-100 text-green-800", else: "bg-yellow-100 text-yellow-800"}"}>
                    <%= payment.status %>
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <%= Calendar.strftime(payment.payment_date, "%Y-%m-%d %H:%M") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <div class="flex gap-2">
                    <.button
                      phx-click="show_payment_modal"
                      phx-value-payment_id={payment.id}
                      class="bg-blue-600 hover:bg-blue-700"
                    >
                      View
                    </.button>
                    <.button
                      :if={payment.payment_type_info.type != "Payout"}
                      phx-click="show_refund_modal"
                      phx-value-payment_id={payment.id}
                      class="bg-red-600 hover:bg-red-700"
                      disabled={payment.status == :refunded}
                    >
                      Refund
                    </.button>
                    <.button
                      :if={payment.payment_type_info.type == "Payout"}
                      phx-click="show_payout_modal"
                      phx-value-payment_id={payment.id}
                      class="bg-green-600 hover:bg-green-700"
                    >
                      Payout Details
                    </.button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
          <!-- Pagination Controls for Payments -->
          <div class="flex items-center justify-between px-6 py-4 border-t border-zinc-200">
            <div class="text-sm text-zinc-600">
              Page <%= @payments_page %> • Showing <%= length(@recent_payments) %> entries
            </div>
            <div class="flex gap-2">
              <.button
                phx-click="payments_prev-page"
                disabled={@payments_page == 1}
                class={
                  if @payments_page == 1,
                    do: "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50",
                    else: "bg-blue-600 hover:bg-blue-700"
                }
              >
                Previous
              </.button>
              <.button
                phx-click="payments_next-page"
                disabled={@payments_end?}
                class={
                  if @payments_end?,
                    do: "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50",
                    else: "bg-blue-600 hover:bg-blue-700"
                }
              >
                Next
              </.button>
            </div>
          </div>
        </div>
      </div>
      <!-- Ledger Entries -->
      <div class="mb-8 rounded border">
        <button
          phx-click="toggle_section"
          phx-value-section="ledger_entries"
          class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
        >
          <h2 class="text-xl font-semibold text-zinc-800">Ledger Entries</h2>
          <.icon
            name={
              if @sections_collapsed.ledger_entries,
                do: "hero-chevron-right",
                else: "hero-chevron-down"
            }
            class="w-5 h-5 text-zinc-600"
          />
        </button>
        <div :if={!@sections_collapsed.ledger_entries} class="overflow-hidden">
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
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
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
                  <%= Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <div class="flex flex-col">
                    <span class="font-medium text-zinc-900">
                      <%= entry.account.name %>
                    </span>
                    <span class="text-xs text-zinc-500">
                      <%= String.capitalize(to_string(entry.account.account_type)) %>
                    </span>
                  </div>
                </td>
                <td class="px-6 py-4 text-sm text-zinc-900 max-w-xs">
                  <div class="truncate" title={entry.description}>
                    <%= entry.description %>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_debit_credit_badge_color(entry.debit_credit)}"}>
                    <%= String.capitalize(to_string(entry.debit_credit)) %>
                  </span>
                </td>
                <td class={"px-6 py-4 whitespace-nowrap text-sm font-medium #{get_debit_credit_amount_color(entry.debit_credit)}"}>
                  <%= Money.to_string!(entry.amount) %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                  <%= if entry.payment do %>
                    <span class="font-mono text-xs">
                      <%= entry.payment.reference_id %>
                    </span>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                  <%= if entry.refund do %>
                    <span class="font-mono text-xs">
                      <%= entry.refund.reference_id %>
                    </span>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                  <%= if entry.related_entity_type do %>
                    <div class="flex flex-col">
                      <span class="text-xs font-medium text-zinc-700">
                        <%= String.capitalize(to_string(entry.related_entity_type)) %>
                      </span>
                      <%= if entry.related_entity_id do %>
                        <span class="text-xs font-mono text-zinc-500">
                          <%= String.slice(to_string(entry.related_entity_id), 0..8) %>...
                        </span>
                      <% end %>
                    </div>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </td>
              </tr>
              <tr :if={Enum.empty?(@ledger_entries)}>
                <td colspan="8" class="px-6 py-4 text-center text-sm text-zinc-500">
                  No ledger entries found for the selected date range.
                </td>
              </tr>
            </tbody>
          </table>
          <!-- Pagination Controls for Ledger Entries -->
          <div class="flex items-center justify-between px-6 py-4 border-t border-zinc-200">
            <div class="text-sm text-zinc-600">
              Page <%= @ledger_entries_page %> • Showing <%= length(@ledger_entries) %> entries
            </div>
            <div class="flex gap-2">
              <.button
                phx-click="ledger_entries_prev-page"
                disabled={@ledger_entries_page == 1}
                class={
                  if @ledger_entries_page == 1,
                    do: "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50",
                    else: "bg-blue-600 hover:bg-blue-700"
                }
              >
                Previous
              </.button>
              <.button
                phx-click="ledger_entries_next-page"
                disabled={@ledger_entries_end?}
                class={
                  if @ledger_entries_end?,
                    do: "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50",
                    else: "bg-blue-600 hover:bg-blue-700"
                }
              >
                Next
              </.button>
            </div>
          </div>
        </div>
      </div>
      <!-- Stripe Webhooks -->
      <div class="mb-8 rounded border">
        <button
          phx-click="toggle_section"
          phx-value-section="webhooks"
          class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
        >
          <h2 class="text-xl font-semibold text-zinc-800">Stripe Webhook Events</h2>
          <.icon
            name={
              if @sections_collapsed.webhooks,
                do: "hero-chevron-right",
                else: "hero-chevron-down"
            }
            class="w-5 h-5 text-zinc-600"
          />
        </button>
        <div :if={!@sections_collapsed.webhooks} class="overflow-hidden">
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
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr :for={webhook <- @webhook_events}>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-zinc-900">
                  <%= String.slice(webhook.event_id, 0..20) %>...
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <span class="font-medium"><%= webhook.event_type %></span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_webhook_state_color(webhook.state)}"}>
                    <%= webhook.state %>
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <%= Calendar.strftime(webhook.inserted_at, "%Y-%m-%d %H:%M:%S") %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <.button
                    phx-click="show_webhook_modal"
                    phx-value-webhook_id={webhook.id}
                    class="bg-blue-600 hover:bg-blue-700"
                  >
                    View Details
                  </.button>
                </td>
              </tr>
              <tr :if={Enum.empty?(@webhook_events)}>
                <td colspan="5" class="px-6 py-4 text-center text-sm text-zinc-500">
                  No webhook events found for the selected date range.
                </td>
              </tr>
            </tbody>
          </table>
          <!-- Pagination Controls for Webhooks -->
          <div class="flex items-center justify-between px-6 py-4 border-t border-zinc-200">
            <div class="text-sm text-zinc-600">
              Page <%= @webhooks_page %> • Showing <%= length(@webhook_events) %> entries
            </div>
            <div class="flex gap-2">
              <.button
                phx-click="webhooks_prev-page"
                disabled={@webhooks_page == 1}
                class={
                  if @webhooks_page == 1,
                    do: "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50",
                    else: "bg-blue-600 hover:bg-blue-700"
                }
              >
                Previous
              </.button>
              <.button
                phx-click="webhooks_next-page"
                disabled={@webhooks_end?}
                class={
                  if @webhooks_end?,
                    do: "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50",
                    else: "bg-blue-600 hover:bg-blue-700"
                }
              >
                Next
              </.button>
            </div>
          </div>
        </div>
      </div>
      <!-- Expense Reports -->
      <div class="mb-8 rounded border">
        <button
          phx-click="toggle_section"
          phx-value-section="expense_reports"
          class="w-full flex items-center justify-between p-4 text-left hover:bg-zinc-50 transition-colors"
        >
          <h2 class="text-xl font-semibold text-zinc-800">Expense Reports</h2>
          <.icon
            name={
              if @sections_collapsed.expense_reports,
                do: "hero-chevron-right",
                else: "hero-chevron-down"
            }
            class="w-5 h-5 text-zinc-600"
          />
        </button>
        <div :if={!@sections_collapsed.expense_reports} class="overflow-hidden">
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
                  QuickBooks Sync Status
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  QuickBooks Bill ID
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Submitted At
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-zinc-200">
              <tr :for={expense_report <- @expense_reports}>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-zinc-900">
                  <%= String.slice(to_string(expense_report.id), 0..12) %>...
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <%= if Ecto.assoc_loaded?(expense_report.user) && expense_report.user do %>
                    <div class="flex flex-col">
                      <span class="font-medium text-zinc-900">
                        <%= get_user_display_name(expense_report.user) %>
                      </span>
                      <span class="text-xs text-zinc-500">
                        <%= expense_report.user.email %>
                      </span>
                    </div>
                  <% else %>
                    <span class="text-zinc-400">Unknown</span>
                  <% end %>
                </td>
                <td class="px-6 py-4 text-sm text-zinc-900 max-w-xs">
                  <div class="truncate" title={expense_report.purpose}>
                    <%= expense_report.purpose %>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <.badge type={
                    get_expense_report_status_badge_type(expense_report.status)
                  }>
                    <%= String.capitalize(expense_report.status || "unknown") %>
                  </.badge>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex flex-col">
                    <.badge type={
                      get_quickbooks_sync_status_badge_type(
                        expense_report.quickbooks_sync_status
                      )
                    }>
                      <%= String.capitalize(
                        expense_report.quickbooks_sync_status || "unknown"
                      ) %>
                    </.badge>
                    <%= if expense_report.quickbooks_sync_error do %>
                      <.tooltip
                        tooltip_text={expense_report.quickbooks_sync_error}
                        max_width="max-w-md"
                        text_align="text-left"
                      >
                        <span class="text-xs text-red-600 mt-1 truncate max-w-xs cursor-help">
                          <%= expense_report.quickbooks_sync_error %>
                        </span>
                      </.tooltip>
                    <% end %>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-600">
                  <%= if expense_report.quickbooks_bill_id do %>
                    <span class="font-mono text-xs">
                      <%= String.slice(expense_report.quickbooks_bill_id, 0..20) %>...
                    </span>
                  <% else %>
                    <span class="text-zinc-400">—</span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-zinc-900">
                  <%= Calendar.strftime(
                    expense_report.inserted_at,
                    "%Y-%m-%d %H:%M"
                  ) %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  <.button
                    phx-click="show_expense_report_status_modal"
                    phx-value-expense_report_id={expense_report.id}
                    class="bg-blue-600 hover:bg-blue-700"
                  >
                    View
                  </.button>
                </td>
              </tr>
              <tr :if={Enum.empty?(@expense_reports)}>
                <td colspan="8" class="px-6 py-4 text-center text-sm text-zinc-500">
                  No submitted expense reports found for the selected date range.
                </td>
              </tr>
            </tbody>
          </table>
          <!-- Pagination Controls for Expense Reports -->
          <div class="flex items-center justify-between px-6 py-4 border-t border-zinc-200">
            <div class="text-sm text-zinc-600">
              Page <%= @expense_reports_page %> • Showing <%= length(
                @expense_reports
              ) %> entries
            </div>
            <div class="flex gap-2">
              <.button
                phx-click="expense_reports_prev-page"
                disabled={@expense_reports_page == 1}
                class={
                  if @expense_reports_page == 1,
                    do: "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50",
                    else: "bg-blue-600 hover:bg-blue-700"
                }
              >
                Previous
              </.button>
              <.button
                phx-click="expense_reports_next-page"
                disabled={@expense_reports_end?}
                class={
                  if @expense_reports_end?,
                    do: "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50",
                    else: "bg-blue-600 hover:bg-blue-700"
                }
              >
                Next
              </.button>
            </div>
          </div>
        </div>
      </div>
      <!-- Refund Modal -->
      <.modal :if={@live_action == :refund_payment} id="refund-modal" show>
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Process Refund</h3>

        <div class="mb-4">
          <p class="text-sm text-zinc-600">
            <strong>Payment:</strong> <%= @selected_payment.reference_id %>
          </p>
          <p class="text-sm text-zinc-600">
            <strong>Amount:</strong> <%= Money.to_string!(@selected_payment.amount) %>
          </p>
          <p :if={@selected_payment.user} class="text-sm text-zinc-600">
            <strong>User:</strong> <%= @selected_payment.user.email %>
          </p>
        </div>

        <.form
          for={@refund_form}
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
                    <%= ticket.ticket_tier.name %>
                  </div>
                  <div class="text-xs text-zinc-600">
                    Ticket ID: <%= ticket.reference_id || ticket.id %>
                  </div>
                  <div class="text-xs font-medium text-zinc-700 mt-1">
                    <%= cond do
                      ticket.ticket_tier.type == :free ->
                        "Free"

                      ticket.ticket_tier.type == :donation ->
                        "Donation"

                      true ->
                        Money.to_string!(
                          ticket.ticket_tier.price || Money.new(0, :USD)
                        )
                    end %>
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
      <.modal :if={@show_credit_modal} id="credit-modal" show>
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Add Credit</h3>

        <div :if={@selected_user} class="mb-4">
          <p class="text-sm text-zinc-600">
            <strong>User:</strong> {@selected_user.email}
          </p>
        </div>

        <.form
          for={@credit_form}
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
      <.modal :if={@show_webhook_modal && @selected_webhook} id="webhook-modal" show>
        <h3 class="text-lg font-medium text-zinc-900 mb-4">
          Webhook Event Details
        </h3>

        <div class="mb-4 space-y-2">
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Event ID:</strong>
              <span class="text-zinc-600 font-mono text-xs ml-2">
                <%= @selected_webhook.event_id %>
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Event Type:</strong>
              <span class="text-zinc-600 ml-2">
                <%= @selected_webhook.event_type %>
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Provider:</strong>
              <span class="text-zinc-600 ml-2 capitalize">
                <%= @selected_webhook.provider %>
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">State:</strong>
              <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full ml-2 #{get_webhook_state_color(@selected_webhook.state)}"}>
                <%= @selected_webhook.state %>
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Received At:</strong>
              <span class="text-zinc-600 ml-2">
                <%= Calendar.strftime(
                  @selected_webhook.inserted_at,
                  "%Y-%m-%d %H:%M:%S UTC"
                ) %>
              </span>
            </p>
          </div>
          <div>
            <p class="text-sm">
              <strong class="text-zinc-900">Last Updated:</strong>
              <span class="text-zinc-600 ml-2">
                <%= Calendar.strftime(
                  @selected_webhook.updated_at,
                  "%Y-%m-%d %H:%M:%S UTC"
                ) %>
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
        show
      >
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Payout Details</h3>

        <div class="mb-6 space-y-3">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-sm font-medium text-zinc-700">Stripe Payout ID</p>
              <p class="text-sm text-zinc-900 font-mono">
                <%= @selected_payout.stripe_payout_id %>
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Status</p>
              <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_payout_status_color(@selected_payout.status)}"}>
                <%= String.capitalize(@selected_payout.status || "unknown") %>
              </span>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Payout Amount</p>
              <p class="text-sm text-zinc-900 font-semibold">
                <%= Money.to_string!(@selected_payout.amount) %>
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Total Fees</p>
              <p class="text-sm text-zinc-900 font-semibold text-red-600">
                <%= Money.to_string!(
                  @selected_payout.fee_total || Money.new(0, :USD)
                ) %>
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Arrival Date</p>
              <p class="text-sm text-zinc-900">
                <%= if @selected_payout.arrival_date do %>
                  <%= Calendar.strftime(
                    @selected_payout.arrival_date,
                    "%Y-%m-%d %H:%M"
                  ) %>
                <% else %>
                  N/A
                <% end %>
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Created</p>
              <p class="text-sm text-zinc-900">
                <%= Calendar.strftime(
                  @selected_payout.inserted_at,
                  "%Y-%m-%d %H:%M"
                ) %>
              </p>
            </div>
          </div>
        </div>
        <!-- Associated Payments -->
        <div class="mb-6">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            Associated Payments (<%= length(@selected_payout.payments || []) %>)
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
                    Date
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={payment <- @selected_payout.payments}>
                  <td class="px-4 py-2 whitespace-nowrap font-mono text-xs">
                    <%= payment.reference_id %>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <%= if Ecto.assoc_loaded?(payment.user) && payment.user do %>
                      <div class="flex flex-col">
                        <span class="text-xs font-medium">
                          <%= get_user_display_name(payment.user) %>
                        </span>
                        <span class="text-xs text-zinc-500">
                          <%= payment.user.email %>
                        </span>
                      </div>
                    <% else %>
                      <span class="text-xs text-zinc-400">System</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap font-medium">
                    <%= Money.to_string!(payment.amount) %>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{if payment.status == :completed, do: "bg-green-100 text-green-800", else: "bg-yellow-100 text-yellow-800"}"}>
                      <%= payment.status %>
                    </span>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap text-xs">
                    <%= Calendar.strftime(payment.payment_date, "%Y-%m-%d %H:%M") %>
                  </td>
                </tr>
              </tbody>
            </table>
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
            Associated Refunds (<%= length(@selected_payout.refunds || []) %>)
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
                    Date
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={refund <- @selected_payout.refunds}>
                  <td class="px-4 py-2 whitespace-nowrap font-mono text-xs">
                    <%= refund.reference_id %>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <%= if Ecto.assoc_loaded?(refund.user) && refund.user do %>
                      <div class="flex flex-col">
                        <span class="text-xs font-medium">
                          <%= get_user_display_name(refund.user) %>
                        </span>
                        <span class="text-xs text-zinc-500">
                          <%= refund.user.email %>
                        </span>
                      </div>
                    <% else %>
                      <span class="text-xs text-zinc-400">System</span>
                    <% end %>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap font-medium text-red-600">
                    <%= Money.to_string!(refund.amount) %>
                  </td>
                  <td class="px-4 py-2 text-xs text-zinc-600 max-w-xs">
                    <div class="truncate" title={refund.reason}>
                      <%= refund.reason || "N/A" %>
                    </div>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap">
                    <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{if refund.status == :completed, do: "bg-green-100 text-green-800", else: "bg-yellow-100 text-yellow-800"}"}>
                      <%= refund.status %>
                    </span>
                  </td>
                  <td class="px-4 py-2 whitespace-nowrap text-xs">
                    <%= Calendar.strftime(refund.inserted_at, "%Y-%m-%d %H:%M") %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p
            :if={length(@selected_payout.refunds || []) == 0}
            class="text-sm text-zinc-500 italic"
          >
            No refunds associated with this payout.
          </p>
        </div>
        <!-- Summary -->
        <div class="mb-4 p-4 bg-zinc-50 rounded border">
          <h4 class="text-sm font-semibold text-zinc-800 mb-2">Summary</h4>
          <div class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p class="text-zinc-600">Total Payments:</p>
              <p class="font-semibold text-zinc-900">
                <%= Money.to_string!(
                  (@selected_payout.payments || [])
                  |> Enum.reduce(Money.new(0, :USD), fn payment, acc ->
                    case Money.add(acc, payment.amount) do
                      {:ok, total} -> total
                      {:error, _} -> acc
                    end
                  end)
                ) %>
              </p>
            </div>
            <div>
              <p class="text-zinc-600">Total Refunds:</p>
              <p class="font-semibold text-red-600">
                <%= Money.to_string!(
                  (@selected_payout.refunds || [])
                  |> Enum.reduce(Money.new(0, :USD), fn refund, acc ->
                    case Money.add(acc, refund.amount) do
                      {:ok, total} -> total
                      {:error, _} -> acc
                    end
                  end)
                ) %>
              </p>
            </div>
            <div>
              <p class="text-zinc-600">Net Amount:</p>
              <p class="font-semibold text-zinc-900">
                <%= Money.to_string!(@selected_payout.amount) %>
              </p>
            </div>
            <div>
              <p class="text-zinc-600">Stripe Fees:</p>
              <p class="font-semibold text-red-600">
                <%= Money.to_string!(
                  @selected_payout.fee_total || Money.new(0, :USD)
                ) %>
              </p>
            </div>
          </div>
        </div>

        <div class="flex justify-end gap-2">
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
      >
        <h3 class="text-lg font-medium text-zinc-900 mb-4">Payment Details</h3>

        <div class="mb-6 space-y-4">
          <!-- Payment Information -->
          <div class="grid grid-cols-2 gap-4">
            <div>
              <p class="text-sm font-medium text-zinc-700">Reference ID</p>
              <p class="text-sm text-zinc-900 font-mono">
                <%= @selected_payment.reference_id %>
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Status</p>
              <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{if @selected_payment.status == :completed, do: "bg-green-100 text-green-800", else: "bg-yellow-100 text-yellow-800"}"}>
                <%= String.capitalize(
                  to_string(@selected_payment.status || "unknown")
                ) %>
              </span>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Amount</p>
              <p class="text-sm text-zinc-900 font-semibold">
                <%= Money.to_string!(@selected_payment.amount) %>
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">Payment Date</p>
              <p class="text-sm text-zinc-900">
                <%= Calendar.strftime(
                  @selected_payment.payment_date,
                  "%Y-%m-%d %H:%M"
                ) %>
              </p>
            </div>
            <div>
              <p class="text-sm font-medium text-zinc-700">User</p>
              <p class="text-sm text-zinc-900">
                <%= if Ecto.assoc_loaded?(@selected_payment.user) && @selected_payment.user do %>
                  <div class="flex flex-col">
                    <span class="font-medium">
                      <%= get_user_display_name(@selected_payment.user) %>
                    </span>
                    <span class="text-xs text-zinc-500">
                      <%= @selected_payment.user.email %>
                    </span>
                  </div>
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
                    <%= @selected_payment.payment_type_info.type %>
                  </span>
                  <%= if @selected_payment.payment_type_info.details do %>
                    <span class="text-xs text-zinc-500 block mt-1">
                      <%= @selected_payment.payment_type_info.details %>
                    </span>
                  <% end %>
                <% else %>
                  <span class="text-zinc-400">Unknown</span>
                <% end %>
              </p>
            </div>
            <div :if={@selected_payment.external_payment_id}>
              <p class="text-sm font-medium text-zinc-700">Stripe Payment ID</p>
              <p class="text-sm text-zinc-900 font-mono text-xs">
                <%= String.slice(@selected_payment.external_payment_id, 0..20) %>...
              </p>
            </div>
            <div :if={@selected_payment.quickbooks_sales_receipt_id}>
              <p class="text-sm font-medium text-zinc-700">QuickBooks Receipt ID</p>
              <p class="text-sm text-green-600 font-mono text-xs">
                <%= @selected_payment.quickbooks_sales_receipt_id %>
              </p>
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
                    <strong>Reference:</strong> <%= booking.reference_id ||
                      booking.id %>
                  </p>
                  <p>
                    <strong>Check-in:</strong> <%= Calendar.strftime(
                      booking.checkin_date,
                      "%Y-%m-%d"
                    ) %>
                  </p>
                  <p>
                    <strong>Check-out:</strong> <%= Calendar.strftime(
                      booking.checkout_date,
                      "%Y-%m-%d"
                    ) %>
                  </p>
                  <p>
                    <strong>Status:</strong> <%= String.capitalize(
                      to_string(booking.status)
                    ) %>
                  </p>
                </div>
              <% {:ticket_order, ticket_order} -> %>
                <div class="text-sm text-zinc-700">
                  <p><strong>Type:</strong> Ticket Order</p>
                  <p>
                    <strong>Reference:</strong> <%= ticket_order.reference_id ||
                      ticket_order.id %>
                  </p>
                  <%= if ticket_order.event do %>
                    <p><strong>Event:</strong> <%= ticket_order.event.title %></p>
                  <% end %>
                  <p>
                    <strong>Tickets:</strong> <%= length(ticket_order.tickets || []) %>
                  </p>
                  <p>
                    <strong>Status:</strong> <%= String.capitalize(
                      to_string(ticket_order.status)
                    ) %>
                  </p>
                </div>
            <% end %>
          </div>
          <!-- Refunds Section -->
          <div class="mt-4">
            <h4 class="text-md font-semibold text-zinc-800 mb-3">
              Refunds (<%= length(@payment_refunds || []) %>)
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
                      Date
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-zinc-200">
                  <tr :for={refund <- @payment_refunds}>
                    <td class="px-4 py-2 whitespace-nowrap font-mono text-xs">
                      <%= refund.reference_id %>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap font-medium text-red-600">
                      <%= Money.to_string!(refund.amount) %>
                    </td>
                    <td class="px-4 py-2 text-xs text-zinc-600 max-w-xs">
                      <div class="truncate" title={refund.reason}>
                        <%= refund.reason || "N/A" %>
                      </div>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap">
                      <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{if refund.status == :completed, do: "bg-green-100 text-green-800", else: "bg-yellow-100 text-yellow-800"}"}>
                        <%= String.capitalize(to_string(refund.status || "unknown")) %>
                      </span>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap text-xs">
                      <%= Calendar.strftime(refund.inserted_at, "%Y-%m-%d %H:%M") %>
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
              Ledger Entries (<%= length(@payment_ledger_entries || []) %>)
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
                          <%= entry.account.name %>
                        </span>
                        <span class="text-xs text-zinc-500">
                          <%= String.capitalize(
                            to_string(entry.account.account_type)
                          ) %>
                        </span>
                      </div>
                    </td>
                    <td class="px-4 py-2 text-xs text-zinc-600 max-w-xs">
                      <div class="truncate" title={entry.description}>
                        <%= entry.description %>
                      </div>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap">
                      <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{get_debit_credit_badge_color(entry.debit_credit)}"}>
                        <%= String.capitalize(to_string(entry.debit_credit)) %>
                      </span>
                    </td>
                    <td class={"px-4 py-2 whitespace-nowrap text-xs font-medium #{get_debit_credit_amount_color(entry.debit_credit)}"}>
                      <%= Money.to_string!(entry.amount) %>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap text-xs">
                      <%= Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M") %>
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
                <%= String.slice(to_string(@selected_expense_report.id), 0..20) %>...
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">User</p>
              <p class="text-zinc-900">
                <%= if Ecto.assoc_loaded?(@selected_expense_report.user) && @selected_expense_report.user do %>
                  <%= get_user_display_name(@selected_expense_report.user) %> (<%= @selected_expense_report.user.email %>)
                <% else %>
                  <span class="text-zinc-400">Unknown</span>
                <% end %>
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Purpose</p>
              <p class="text-zinc-900"><%= @selected_expense_report.purpose %></p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Reimbursement Method</p>
              <p class="text-zinc-900">
                <%= String.capitalize(
                  @selected_expense_report.reimbursement_method || "unknown"
                ) %>
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Status</p>
              <p class="text-zinc-900">
                <.badge type={
                  get_expense_report_status_badge_type(
                    @selected_expense_report.status
                  )
                }>
                  <%= String.capitalize(
                    @selected_expense_report.status || "unknown"
                  ) %>
                </.badge>
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Certification Accepted</p>
              <p class="text-zinc-900">
                <%= if @selected_expense_report.certification_accepted,
                  do: "Yes",
                  else: "No" %>
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Created At</p>
              <p class="text-zinc-900">
                <%= Calendar.strftime(
                  @selected_expense_report.inserted_at,
                  "%Y-%m-%d %H:%M:%S"
                ) %>
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Updated At</p>
              <p class="text-zinc-900">
                <%= Calendar.strftime(
                  @selected_expense_report.updated_at,
                  "%Y-%m-%d %H:%M:%S"
                ) %>
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
                    <%= @selected_expense_report.address.address %><br />
                    <%= @selected_expense_report.address.city %>, <%= @selected_expense_report.address.region %> <%= @selected_expense_report.address.postal_code %>
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
                    Account ending in: <%= @selected_expense_report.bank_account.account_number_last_4 %>
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
                  <%= @selected_expense_report.event.title %>
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
                <.badge type={
                  get_quickbooks_sync_status_badge_type(
                    @selected_expense_report.quickbooks_sync_status
                  )
                }>
                  <%= String.capitalize(
                    @selected_expense_report.quickbooks_sync_status || "unknown"
                  ) %>
                </.badge>
              </p>
            </div>
            <%= if @selected_expense_report.quickbooks_bill_id do %>
              <div>
                <p class="font-medium text-zinc-700">QuickBooks Bill ID</p>
                <p class="text-zinc-900 font-mono text-xs">
                  <%= @selected_expense_report.quickbooks_bill_id %>
                </p>
              </div>
            <% end %>
            <%= if @selected_expense_report.quickbooks_vendor_id do %>
              <div>
                <p class="font-medium text-zinc-700">QuickBooks Vendor ID</p>
                <p class="text-zinc-900 font-mono text-xs">
                  <%= @selected_expense_report.quickbooks_vendor_id %>
                </p>
              </div>
            <% end %>
            <%= if @selected_expense_report.quickbooks_synced_at do %>
              <div>
                <p class="font-medium text-zinc-700">Synced At</p>
                <p class="text-zinc-900">
                  <%= Calendar.strftime(
                    @selected_expense_report.quickbooks_synced_at,
                    "%Y-%m-%d %H:%M:%S"
                  ) %>
                </p>
              </div>
            <% end %>
            <%= if @selected_expense_report.quickbooks_last_sync_attempt_at do %>
              <div>
                <p class="font-medium text-zinc-700">Last Sync Attempt</p>
                <p class="text-zinc-900">
                  <%= Calendar.strftime(
                    @selected_expense_report.quickbooks_last_sync_attempt_at,
                    "%Y-%m-%d %H:%M:%S"
                  ) %>
                </p>
              </div>
            <% end %>
            <%= if @selected_expense_report.quickbooks_sync_error do %>
              <div class="col-span-2">
                <p class="font-medium text-zinc-700">Sync Error</p>
                <p class="text-red-600 text-xs">
                  <%= @selected_expense_report.quickbooks_sync_error %>
                </p>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Expense Items -->
        <div class="mb-6">
          <h4 class="text-md font-semibold text-zinc-800 mb-3">
            Expense Items (<%= length(@selected_expense_report.expense_items || []) %>)
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
                      <%= Calendar.strftime(item.date, "%Y-%m-%d") %>
                    </td>
                    <td class="px-4 py-2"><%= item.vendor %></td>
                    <td class="px-4 py-2 max-w-xs">
                      <div class="truncate" title={item.description}>
                        <%= item.description %>
                      </div>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap font-medium">
                      <%= Money.to_string!(item.amount) %>
                    </td>
                    <td class="px-4 py-2">
                      <%= if item.receipt_s3_path do %>
                        <a
                          href={ExpenseReports.receipt_url(item.receipt_s3_path)}
                          target="_blank"
                          class="text-blue-600 hover:text-blue-800 text-xs"
                        >
                          View Receipt
                        </a>
                      <% else %>
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
            Income Items (<%= length(@selected_expense_report.income_items || []) %>)
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
                      <%= Calendar.strftime(item.date, "%Y-%m-%d") %>
                    </td>
                    <td class="px-4 py-2 max-w-xs">
                      <div class="truncate" title={item.description}>
                        <%= item.description %>
                      </div>
                    </td>
                    <td class="px-4 py-2 whitespace-nowrap font-medium">
                      <%= Money.to_string!(item.amount) %>
                    </td>
                    <td class="px-4 py-2">
                      <%= if item.proof_s3_path do %>
                        <a
                          href={ExpenseReports.receipt_url(item.proof_s3_path)}
                          target="_blank"
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
                <%= Money.to_string!(totals.expense_total) %>
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Income Total</p>
              <p class="text-lg font-semibold text-zinc-900">
                <%= Money.to_string!(totals.income_total) %>
              </p>
            </div>
            <div>
              <p class="font-medium text-zinc-700">Net Total</p>
              <p class="text-lg font-semibold text-zinc-900">
                <%= Money.to_string!(totals.net_total) %>
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
      {:ok, date} -> DateTime.new!(date, time)
      {:error, _} -> DateTime.utc_now()
    end
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

  defp get_user_display_name(nil), do: "System"

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

  defp get_normal_balance_badge_color("credit"), do: "bg-blue-100 text-blue-800"

  defp get_normal_balance_badge_color("debit"),
    do: "bg-purple-100 text-purple-800"

  defp get_normal_balance_badge_color(:credit), do: "bg-blue-100 text-blue-800"

  defp get_normal_balance_badge_color(:debit),
    do: "bg-purple-100 text-purple-800"

  defp get_normal_balance_badge_color(_), do: "bg-zinc-100 text-zinc-800"

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

  defp get_payout_status_color(status) do
    case String.downcase(to_string(status || "")) do
      "paid" -> "bg-green-100 text-green-800"
      "pending" -> "bg-yellow-100 text-yellow-800"
      "failed" -> "bg-red-100 text-red-800"
      "canceled" -> "bg-zinc-100 text-zinc-800"
      _ -> "bg-zinc-100 text-zinc-800"
    end
  end

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

  defp get_expense_report_status_badge_type(status) do
    case String.downcase(to_string(status || "")) do
      "draft" -> "dark"
      "submitted" -> "default"
      "approved" -> "green"
      "rejected" -> "red"
      "paid" -> "sky"
      _ -> "dark"
    end
  end

  defp get_quickbooks_sync_status_badge_type(status) do
    case String.downcase(to_string(status || "")) do
      "pending" -> "yellow"
      "synced" -> "green"
      "failed" -> "red"
      "processing" -> "default"
      _ -> "dark"
    end
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
          require Logger

          Logger.info("Booking refunded and dates released after refund",
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
               "Refund processed - tickets released"
             ) do
          {:ok, _canceled_order} ->
            require Logger

            Logger.info(
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
