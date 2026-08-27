defmodule Ysc.Tickets.AdminGrants do
  @moduledoc """
  Admin-granted complimentary tickets for members (e.g. migration from legacy systems).

  Creates completed $0 ticket orders with confirmed tickets immediately, without checkout.
  """

  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ysc.Accounts
  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Events.EventDateTime
  alias Ysc.Events.Ticket
  alias Ysc.Events.TicketTier
  alias Ysc.Events.TicketTierHelpers
  alias Ysc.Repo
  alias Ysc.Tickets.BookingLocker
  alias Ysc.Tickets.CheckoutCancel
  alias Ysc.Tickets.TicketOrder

  @doc """
  Grants confirmed tickets to a member for an event.

  ## Parameters

    * `granted_by_id` - admin user performing the grant
    * `user_id` - member receiving tickets
    * `event_id` - event id
    * `ticket_selections` - map of `ticket_tier_id => quantity`
    * `opts` - `:skip_capacity`, `:skip_sale_guards`, `:skip_email`, `:admin_grant_notes`

  ## Returns

    * `{:ok, %TicketOrder{}}` with tickets preloaded
    * `{:error, reason}` or `{:error, %Ecto.Changeset{}}`
  """
  def grant_admin_tickets(
        granted_by_id,
        user_id,
        event_id,
        ticket_selections,
        opts \\ []
      )
      when is_map(ticket_selections) do
    skip_capacity? = Keyword.get(opts, :skip_capacity, false)
    skip_sale_guards? = Keyword.get(opts, :skip_sale_guards, false)
    admin_grant_notes = Keyword.get(opts, :admin_grant_notes)

    Ysc.Logging.info("Admin ticket grant started",
      granted_by_id: granted_by_id,
      user_id: user_id,
      event_id: event_id,
      ticket_selections: ticket_selections,
      skip_capacity: skip_capacity?,
      skip_sale_guards: skip_sale_guards?
    )

    result =
      with {:ok, user} <- fetch_user(user_id),
           {:ok, event} <- fetch_grantable_event(event_id),
           {:ok, tiers} <- load_and_validate_tiers(event_id, ticket_selections),
           :ok <- validate_recipient_for_registration_tiers(user, tiers),
           :ok <- ensure_no_blocking_pending_checkout(user_id, event_id),
           :ok <- reconcile_pending_checkouts_for_grant(user_id, event_id),
           :ok <-
             maybe_validate_fulfillment(
               user_id,
               event_id,
               ticket_selections,
               skip_capacity: skip_capacity?,
               skip_sale_guards: skip_sale_guards?
             ) do
        insert_grant_transaction(
          granted_by_id,
          user,
          event,
          tiers,
          ticket_selections,
          admin_grant_notes,
          skip_capacity: skip_capacity?,
          skip_sale_guards: skip_sale_guards?
        )
      end

    case result do
      {:ok, ticket_order} ->
        Ysc.Logging.info("Admin ticket grant succeeded",
          granted_by_id: granted_by_id,
          user_id: user_id,
          event_id: event_id,
          ticket_order_id: ticket_order.id,
          ticket_count: length(ticket_order.tickets || [])
        )

        {:ok, ticket_order}

      {:error, reason} = error ->
        Ysc.Logging.info("Admin ticket grant failed",
          granted_by_id: granted_by_id,
          user_id: user_id,
          event_id: event_id,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    event_id = Fixtures.ulid()
    tier_ids = [Fixtures.ulid()]

    from(tt in TicketTier,
      where: tt.id in ^tier_ids and tt.event_id == ^event_id
    )
  end

  @doc false
  def ci_query_explain_pending_orders_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    pending_orders_query(Fixtures.ulid(), Fixtures.ulid())
  end

  defp fetch_user(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp fetch_grantable_event(event_id) do
    # An event can carry a Partiful link alongside real YSC ticket tiers
    # (see TicketTierManagement); grants are validated against those tiers by
    # load_and_validate_tiers/2, so the presence of a Partiful link alone does
    # not disqualify a grant.
    case Repo.get(Event, event_id) do
      nil -> {:error, :event_not_found}
      %Event{} = event -> {:ok, event}
    end
  end

  defp load_and_validate_tiers(event_id, ticket_selections) do
    if ticket_selections == %{} do
      {:error, :empty_selection}
    else
      tier_ids = Map.keys(ticket_selections)

      tiers =
        TicketTier
        |> where([tt], tt.id in ^tier_ids and tt.event_id == ^event_id)
        |> Repo.all()

      if length(tiers) != length(tier_ids) do
        {:error, :invalid_ticket_tier}
      else
        case Enum.find(tiers, &TicketTierHelpers.donation_tier?/1) do
          nil ->
            case invalid_quantity?(ticket_selections) do
              true -> {:error, :invalid_quantity}
              false -> {:ok, tiers}
            end

          _ ->
            {:error, :donation_tier_not_grantable}
        end
      end
    end
  end

  defp invalid_quantity?(ticket_selections) do
    Enum.any?(ticket_selections, fn {_tier_id, quantity} ->
      not is_integer(quantity) or quantity < 1
    end)
  end

  defp ensure_no_blocking_pending_checkout(user_id, event_id, opts \\ []) do
    context = Keyword.get(opts, :context, "admin_grant_precheck")

    case CheckoutCancel.blocking_pending_orders(user_id, event_id) do
      [] ->
        :ok

      orders ->
        Ysc.Logging.info(
          "Admin ticket grant blocked by in-flight checkout payment",
          context: context,
          user_id: user_id,
          event_id: event_id,
          pending_order_ids: Enum.map(orders, & &1.id)
        )

        {:error, :checkout_payment_in_progress}
    end
  end

  # Close the same checkout-abandonment race #1130 fixed in cancel_ticket_order/3:
  # a point-in-time PaymentIntent status read can go stale, so locally cancelling
  # a cart that still looks like `requires_payment_method` orphans a charge that
  # completes moments later. Stripe-cancel those carts before inserting the grant.
  # 3DS / processing / already-succeeded carts are left for
  # `ensure_no_blocking_pending_checkout/3` rather than cancelled out from under
  # an in-progress payment.
  defp reconcile_pending_checkouts_for_grant(user_id, event_id) do
    pending_orders_for_event(user_id, event_id)
    |> Enum.reduce_while(:ok, fn order, :ok ->
      cond do
        not payment_intent_attached?(order) ->
          reconcile_safe_pending_checkout(order)

        CheckoutCancel.pending_order_safe_to_cancel?(order,
          context: "admin_grant"
        ) ->
          reconcile_safe_pending_checkout(order)

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp reconcile_safe_pending_checkout(order) do
    case Ysc.Tickets.cancel_ticket_order(
           order,
           "Superseded by admin ticket grant",
           context: "admin_grant"
         ) do
      {:ok, %TicketOrder{status: :completed} = completed} ->
        Ysc.Logging.info(
          "Admin ticket grant aborted: pending checkout payment had already succeeded and was fulfilled",
          ticket_order_id: completed.id,
          user_id: completed.user_id,
          event_id: completed.event_id
        )

        {:halt, {:error, :checkout_payment_in_progress}}

      {:ok, _} ->
        {:cont, :ok}

      {:error, {:payment_succeeded_fulfillment_failed, fulfillment_error}} ->
        Ysc.Logging.error(
          "Admin ticket grant aborted: checkout payment succeeded but could not be fulfilled",
          ticket_order_id: order.id,
          error: inspect(fulfillment_error)
        )

        {:halt, {:error, :checkout_payment_in_progress}}

      {:error, _reason} ->
        {:halt, {:error, :checkout_payment_in_progress}}
    end
  end

  defp maybe_validate_fulfillment(user_id, event_id, ticket_selections, opts) do
    case BookingLocker.validate_fulfillment_capacity(
           user_id,
           event_id,
           ticket_selections,
           opts
         ) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_validate_fulfillment_in_transaction(
         user_id,
         event_id,
         ticket_selections,
         opts
       ) do
    case BookingLocker.validate_fulfillment_capacity_in_transaction(
           user_id,
           event_id,
           ticket_selections,
           opts
         ) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_recipient_for_registration_tiers(user, tiers) do
    if Enum.any?(tiers, & &1.requires_registration) and
         not registration_profile_complete?(user) do
      {:error, :incomplete_member_profile}
    else
      :ok
    end
  end

  defp registration_profile_complete?(user) do
    present?(user.first_name) and present?(user.last_name) and
      present?(user.email)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp insert_grant_transaction(
         granted_by_id,
         user,
         event,
         tiers,
         ticket_selections,
         admin_grant_notes,
         grant_opts
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = grant_expires_at(event, now)
    tiers_by_id = Map.new(tiers, &{&1.id, &1})

    Repo.transaction(fn ->
      order_attrs = %{
        user_id: user.id,
        event_id: event.id,
        total_amount: Money.new(0, :USD),
        discount_amount: Money.new(0, :USD),
        expires_at: expires_at,
        completed_at: now,
        granted_by_id: granted_by_id,
        admin_grant_notes: admin_grant_notes
      }

      with :ok <-
             maybe_validate_fulfillment_in_transaction(
               user.id,
               event.id,
               ticket_selections,
               grant_opts
             ),
           {:ok, ticket_order} <- insert_ticket_order(order_attrs),
           {:ok, _fulfilled_reservations} <-
             BookingLocker.fulfill_reservations_for_selections(
               user.id,
               event.id,
               ticket_order.id,
               ticket_selections
             ),
           :ok <-
             cancel_pending_ticket_orders_for_grant(
               user.id,
               event.id,
               ticket_order.id
             ),
           {:ok, tickets} <-
             insert_tickets_for_selections(
               ticket_order,
               user,
               tiers_by_id,
               ticket_selections,
               expires_at
             ),
           :ok <- maybe_insert_registration_details(tickets, tiers_by_id, user),
           :ok <-
             ensure_no_blocking_pending_checkout(
               user.id,
               event.id,
               context: "admin_grant_transaction"
             ) do
        ticket_order
        |> Repo.preload(tickets: :ticket_tier)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, ticket_order} -> {:ok, ticket_order}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_ticket_order(%{granted_by_id: granted_by_id} = attrs) do
    order_attrs = Map.delete(attrs, :granted_by_id)

    %TicketOrder{}
    |> TicketOrder.admin_grant_changeset(order_attrs, granted_by_id)
    |> Repo.insert_with_reference_retry(TicketOrder)
  end

  defp insert_tickets_for_selections(
         ticket_order,
         user,
         tiers_by_id,
         ticket_selections,
         expires_at
       ) do
    ticket_selections
    |> Enum.flat_map(fn {tier_id, quantity} ->
      tier = Map.fetch!(tiers_by_id, tier_id)

      Enum.map(1..quantity, fn _ ->
        %Ticket{}
        |> Ticket.admin_grant_changeset(%{
          event_id: ticket_order.event_id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          ticket_order_id: ticket_order.id,
          status: :confirmed,
          expires_at: expires_at,
          discount_amount: Money.new(0, :USD)
        })
      end)
    end)
    |> Enum.reduce_while({:ok, []}, fn changeset, {:ok, acc} ->
      case Repo.insert_with_reference_retry(changeset, Ticket) do
        {:ok, ticket} ->
          {:cont, {:ok, [ticket | acc]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp maybe_insert_registration_details(tickets, tiers_by_id, user) do
    details =
      Enum.flat_map(tickets, fn ticket ->
        tier = Map.fetch!(tiers_by_id, ticket.ticket_tier_id)

        if tier.requires_registration do
          [
            %{
              ticket_id: ticket.id,
              first_name: user.first_name,
              last_name: user.last_name,
              email: user.email
            }
          ]
        else
          []
        end
      end)

    if details == [] do
      :ok
    else
      case Events.create_ticket_details(details) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp cancel_pending_ticket_orders_for_grant(user_id, event_id, grant_order_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # The grant order is already `:completed`, so it is not in this pending set.
    pending_orders = pending_orders_for_event(user_id, event_id)

    {with_payment_intent, without_payment_intent} =
      Enum.split_with(pending_orders, fn order ->
        payment_intent_attached?(order)
      end)

    # A remaining PaymentIntent-backed cart must not be cancelled locally —
    # that is the #1130 orphan-charge race. Fail the grant; in-flight payments
    # are also caught by the trailing ensure_no_blocking_pending_checkout/3.
    if with_payment_intent != [] do
      {:error, :checkout_payment_in_progress}
    else
      cancel_pending_orders_without_payment_intent(
        without_payment_intent,
        user_id,
        event_id,
        grant_order_id,
        now
      )
    end
  end

  defp cancel_pending_orders_without_payment_intent(
         pending_orders,
         user_id,
         event_id,
         grant_order_id,
         now
       ) do
    pending_order_ids = Enum.map(pending_orders, & &1.id)

    if pending_order_ids == [] do
      :ok
    else
      {order_count, _} =
        from(to in TicketOrder, where: to.id in ^pending_order_ids)
        |> Repo.update_all(
          set: [
            status: :cancelled,
            cancelled_at: now,
            cancellation_reason: "Superseded by admin ticket grant",
            updated_at: now
          ]
        )

      {ticket_count, _} =
        from(t in Ticket,
          where:
            t.ticket_order_id in ^pending_order_ids and t.status == :pending
        )
        |> Repo.update_all(set: [status: :cancelled, updated_at: now])

      Ysc.Logging.info(
        "Cancelled pending ticket orders superseded by admin grant",
        user_id: user_id,
        event_id: event_id,
        grant_order_id: grant_order_id,
        cancelled_order_count: order_count,
        cancelled_ticket_count: ticket_count
      )

      :ok
    end
  end

  defp pending_orders_for_event(user_id, event_id) do
    user_id
    |> pending_orders_query(event_id)
    |> Repo.all()
  end

  defp pending_orders_query(user_id, event_id) do
    from(to in TicketOrder,
      where:
        to.user_id == ^user_id and to.event_id == ^event_id and
          to.status == :pending
    )
  end

  defp payment_intent_attached?(order) do
    case order.payment_intent_id do
      id when is_binary(id) and id != "" -> true
      _unattached -> false
    end
  end

  defp grant_expires_at(%Event{} = event, now) do
    end_date = event.end_date || event.start_date
    end_time = event.end_time || event.start_time

    case EventDateTime.combine(end_date, end_time) do
      %DateTime{} = end_dt -> end_dt
      _ -> DateTime.add(now, 365, :day)
    end
  end
end
