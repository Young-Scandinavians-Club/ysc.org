defmodule Ysc.Merch.PrintfulEvents do
  @moduledoc """
  Applies what Printful tells us about an order to our records: status,
  shipments and tracking, the real cost, and the notifications that go with
  each change.

  The same logic serves two sources: Printful's webhooks
  (`handle_event/2`) and our periodic poll (`sync_order/2`), which is the
  safety net for missed webhooks. Both are safe to repeat and to receive out of
  order:

    * status only moves forward (in production, then shipped, then delivered),
      never back, and closed orders (failed, canceled, refunded, delivered) are
      left alone;
    * a shipment is keyed by Printful's shipment id, and its notification is
      claimed in the same transaction that queues it, so it is sent once, and
      only once the parcel has really shipped and has a tracking number (or
      has waited long enough for one);
    * a failure or cancellation notifies once, when the status actually changes.

  Events for orders that aren't ours (no matching reference) are ignored.
  """
  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ecto.Multi
  alias Ysc.Merch.{Notifications, Order, OrderItem, Orders, Shipment, Variant}
  alias Ysc.Printful.Amount
  alias Ysc.Repo

  # Statuses an event may still change. Shipped orders can still be marked
  # delivered or returned, but can no longer fail or be canceled.
  @before_shipment [:paid, :submitting, :submitted, :in_production]
  # A shipped parcel is announced once it has a tracking number. If Printful
  # still has none this long after the parcel left, announce it without one
  # rather than never telling the member.
  @tracking_grace_seconds 6 * 3600

  @rank %{
    paid: 0,
    submitting: 0,
    submitted: 1,
    in_production: 2,
    shipped: 3,
    delivered: 4
  }

  @doc """
  Webhook event types we ask Printful to send. Only types from Printful's
  webhook documentation: it sends no "delivered" event, so an order never
  reaches `:delivered` on its own (see the `package_delivered` clause below,
  kept for sources that do report delivery).
  """
  def subscribed_types do
    ~w(package_shipped package_returned order_failed order_canceled
       order_put_hold order_put_hold_approval order_remove_hold order_updated
       order_refunded)
  end

  @doc """
  Handles one webhook event: `type` and the payload's `data` object.

  Always returns `:ok` for events that are understood or irrelevant; raises on
  database errors so the Oban job retries.
  """
  @spec handle_event(String.t(), map()) :: :ok
  def handle_event(type, data) when is_binary(type) and is_map(data) do
    printful_order = Map.get(data, "order") || %{}

    case find_order(printful_order) do
      nil ->
        Ysc.Logging.info("Ignoring Printful event for an unknown order",
          type: type,
          printful_order_id: printful_order["id"]
        )

        :ok

      order ->
        order = stamp(order, printful_order)
        dispatch(type, order, data, printful_order)
    end
  end

  def handle_event(_type, _data), do: :ok

  defp dispatch("package_shipped", order, data, po) do
    raw = data["shipment"]

    # The event says the parcel shipped, but a shipment Printful itself still
    # calls something else (pending) has not left the building.
    if left_the_building?(raw) do
      case record_shipment(order, raw, :shipped, po) do
        {:ok, shipment} -> shipped(order, shipment)
        :ignore -> :ok
      end
    else
      :ok
    end
  end

  defp dispatch(type, order, data, po)
       when type in ["package_delivered", "shipment_delivered"] do
    case record_shipment(order, data["shipment"], :delivered, po) do
      {:ok, shipment} -> delivered(order, shipment)
      :ignore -> :ok
    end
  end

  defp dispatch("package_returned", order, data, po) do
    case record_shipment(order, data["shipment"], :returned, po) do
      {:ok, shipment} -> returned(order, shipment)
      :ignore -> :ok
    end
  end

  defp dispatch("order_failed", order, data, po) do
    fail(
      order,
      :failed,
      reason_from(data, po, "Printful could not produce this order")
    )
  end

  defp dispatch("order_canceled", order, data, po) do
    fail(
      order,
      :canceled,
      reason_from(data, po, "Printful canceled this order")
    )
  end

  defp dispatch("order_put_hold", order, data, po) do
    hold(order, reason_from(data, po, "Printful put this order on hold"))
  end

  # Printful paused the order until the club approves a design change. Nothing
  # moves until someone does, so the board has to hear about it.
  defp dispatch("order_put_hold_approval", order, data, po) do
    needs_approval(
      order,
      reason_from(
        data,
        po,
        "Printful needs a design change approved before it can make this order"
      )
    )
  end

  # Printful refunded the club for a confirmed order (usually after a
  # cancellation). The member is not refunded automatically.
  defp dispatch("order_refunded", order, data, _po),
    do: refunded(order, data["amount"])

  defp dispatch("order_updated", order, _data, po), do: sync_order(order, po)
  defp dispatch("order_created", order, _data, po), do: sync_order(order, po)
  defp dispatch(_other, _order, _data, _po), do: :ok

  ## Polling

  @doc """
  Reconciles an order with Printful's full record of it (as returned by
  `GET /orders/{id}`, or carried by an `order_updated` event).
  """
  @spec sync_order(Order.t(), map()) :: :ok
  def sync_order(%Order{} = order, printful_order)
      when is_map(printful_order) do
    order = stamp(order, printful_order)

    # Printful lists a shipment as soon as the order is placed (status
    # "pending", no tracking number), long before anything leaves the building.
    # Only parcels that have actually shipped count.
    shipments =
      printful_order
      |> Map.get("shipments")
      |> List.wrap()
      |> Enum.filter(&shipped?/1)

    Enum.each(shipments, fn raw ->
      # A parcel Printful already reports as delivered or returned is recorded
      # as such, so a missed webhook never turns into a "shipped" email sent
      # after the fact.
      case record_shipment(order, raw, shipment_status(raw), printful_order) do
        {:ok, shipment} -> shipped(order, shipment)
        :ignore -> :ok
      end
    end)

    case printful_order["status"] do
      "inprocess" ->
        advance(order, :in_production)

      "partial" ->
        advance(order, :in_production)

      "fulfilled" ->
        advance(order, :shipped)

      "failed" ->
        fail(
          order,
          :failed,
          reason_from(
            %{},
            printful_order,
            "Printful could not produce this order"
          )
        )

      "canceled" ->
        fail(
          order,
          :canceled,
          reason_from(%{}, printful_order, "Printful canceled this order")
        )

      "onhold" ->
        hold(
          order,
          reason_from(%{}, printful_order, "Printful put this order on hold")
        )

      _ ->
        :ok
    end

    :ok
  end

  # By the shipment's own status when it has one; otherwise it counts if it has
  # a ship date.
  defp shipped?(%{"status" => status}) when is_binary(status),
    do: status in ~w(shipped delivered returned)

  defp shipped?(%{} = shipment),
    do: is_integer(shipment["shipped_at"]) or is_binary(shipment["ship_date"])

  defp shipped?(_), do: false

  # For a webhook that announces a shipment: only an explicit status other than
  # shipped/delivered/returned (i.e. pending) rules it out.
  defp left_the_building?(%{"status" => status}) when is_binary(status),
    do: status in ~w(shipped delivered returned)

  defp left_the_building?(_), do: true

  defp shipment_status(%{"status" => "delivered"}), do: :delivered
  defp shipment_status(%{"status" => "returned"}), do: :returned
  defp shipment_status(_), do: :shipped

  ## Finding and stamping

  defp find_order(%{"external_id" => ref} = po) when is_binary(ref) do
    if String.starts_with?(ref, "MRC-") do
      Orders.get_order_by_reference(ref) || find_by_printful_id(po)
    else
      find_by_printful_id(po)
    end
  end

  defp find_order(po), do: find_by_printful_id(po)

  defp find_by_printful_id(%{"id" => id}) when is_integer(id),
    do: Orders.get_order_by_printful_id(id)

  defp find_by_printful_id(_), do: nil

  # Records that we heard from Printful, fills in the Printful id if we hadn't
  # stored it yet, and keeps the cost current. Returns the order with those
  # changes applied.
  defp stamp(order, printful_order) do
    now = now()

    changes =
      [printful_synced_at: now, updated_at: now]
      |> maybe_put(
        :printful_order_id,
        order.printful_order_id == nil && printful_order["id"]
      )
      |> maybe_put(:printful_cost, cost_from(printful_order))

    from(o in Order, where: o.id == ^order.id) |> Repo.update_all(set: changes)

    struct(order, Map.new(changes))
  end

  defp maybe_put(changes, _key, falsy) when falsy in [nil, false], do: changes
  defp maybe_put(changes, key, value), do: Keyword.put(changes, key, value)

  defp cost_from(%{"costs" => %{"total" => total}}) do
    case Amount.to_money(total) do
      %Money{} = money -> if Money.positive?(money), do: money
      nil -> nil
    end
  end

  defp cost_from(_), do: nil

  defp reason_from(data, po, default) do
    [data["reason"], po["error"], po["status_reason"]]
    |> Enum.find(&(is_binary(&1) and &1 != ""))
    |> Kernel.||(default)
  end

  ## Shipments

  defp record_shipment(_order, nil, _status, _po), do: :ignore

  defp record_shipment(order, %{"id" => id} = raw, status, po)
       when is_integer(id) do
    tracking_number = text(raw["tracking_number"])

    attrs = %{
      order_id: order.id,
      printful_shipment_id: id,
      carrier: text(raw["carrier"]),
      service: text(raw["service"]),
      tracking_number: tracking_number,
      # Before the carrier has a label Printful gives a link with no number in
      # it (".../tracking/<id>/"), which goes nowhere.
      tracking_url: tracking_number && url(raw["tracking_url"]),
      reshipment: raw["reshipment"] == true,
      items: shipment_items(order, raw["items"], po),
      shipped_at: shipped_at(raw)
    }

    case Repo.get_by(Shipment, printful_shipment_id: id) do
      nil -> insert_shipment(order, attrs, status)
      existing -> merge_shipment(order, existing, attrs, status)
    end
  end

  defp record_shipment(_order, _bad, _status, _po), do: :ignore

  # Printful's free text, trimmed and cut to the column; blank is no value.
  defp text(value) when is_binary(value) do
    case value |> String.trim() |> String.slice(0, 255) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp text(value) when is_integer(value), do: Integer.to_string(value)
  defp text(_), do: nil

  # Too long to store means too long to be a real link.
  defp url(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed when byte_size(trimmed) > 1024 -> nil
      trimmed -> trimmed
    end
  end

  defp url(_), do: nil

  # Which of our order lines are in this parcel. Printful's shipment names its
  # items by Printful's own item ids; the order record maps those to the sync
  # variant we sent, which is how we find our line. Anything we cannot place is
  # left out, and an empty result means "unknown" (the whole order is shown).
  defp shipment_items(%{items: order_items}, raw_items, po)
       when is_list(raw_items) and is_list(order_items) do
    sync_by_item =
      po
      |> Map.get("items")
      |> List.wrap()
      |> Enum.flat_map(fn
        %{"id" => id, "sync_variant_id" => sync} when is_integer(id) ->
          [{id, sync}]

        _ ->
          []
      end)
      |> Map.new()

    line_by_sync =
      order_items
      |> Enum.flat_map(fn
        %OrderItem{variant: %Variant{printful_sync_variant_id: sync}} = line
        when is_integer(sync) ->
          [{sync, line}]

        _ ->
          []
      end)
      |> Map.new()

    raw_items
    |> Enum.flat_map(fn
      %{"item_id" => item_id} = raw when is_integer(item_id) ->
        with sync when is_integer(sync) <- sync_by_item[item_id],
             %OrderItem{} = line <- line_by_sync[sync] do
          [{line, parcel_quantity(raw["quantity"], line)}]
        else
          _ -> []
        end

      _ ->
        []
    end)
    |> Enum.group_by(fn {line, _} -> line.id end)
    |> Enum.map(fn {line_id, [{line, _} | _] = entries} ->
      total = entries |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      %{"order_item_id" => line_id, "quantity" => min(total, line.quantity)}
    end)
    |> Enum.sort_by(& &1["order_item_id"])
  end

  defp shipment_items(_order, _raw_items, _po), do: []

  defp parcel_quantity(quantity, _line)
       when is_integer(quantity) and quantity > 0,
       do: quantity

  defp parcel_quantity(_quantity, line), do: line.quantity

  # A webhook and the status poll can report the same new shipment at once.
  # The insert is a no-op if the other one got there first; either way we
  # carry on with whichever row is in the table.
  defp insert_shipment(order, attrs, status) do
    attrs =
      Map.merge(attrs, %{
        status: status,
        shipped_at: attrs.shipped_at || now(),
        delivered_at: if(status == :delivered, do: now())
      })

    {:ok, inserted} =
      %Shipment{}
      |> Shipment.changeset(attrs)
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: :printful_shipment_id
      )

    stored =
      Repo.get_by!(Shipment, printful_shipment_id: attrs.printful_shipment_id)

    if stored.id == inserted.id,
      do: {:ok, stored},
      else: merge_shipment(order, stored, attrs, status)
  end

  # A shipment id belongs to one order. One that turns up on another order's
  # event is ignored rather than moved.
  defp merge_shipment(
         %{id: order_id},
         %{order_id: order_id} = existing,
         attrs,
         status
       ),
       do: {:ok, update_shipment(existing, attrs, status)}

  defp merge_shipment(order, existing, _attrs, _status) do
    Ysc.Logging.warning("Printful shipment reported for a different order",
      order_id: order.id,
      shipment_order_id: existing.order_id,
      printful_shipment_id: existing.printful_shipment_id
    )

    :ignore
  end

  # A shipment only moves forward: shipped -> delivered, or -> returned. A late
  # "shipped" event never reverts a delivered or returned parcel.
  defp update_shipment(existing, attrs, status) do
    next_status = next_shipment_status(existing.status, status)

    changes =
      attrs
      |> Map.take([
        :carrier,
        :service,
        :tracking_number,
        :tracking_url,
        :items,
        :shipped_at
      ])
      |> Enum.reject(fn {_k, v} -> v in [nil, []] end)
      |> Map.new()
      |> Map.put(:status, next_status)
      |> then(fn changes ->
        if next_status == :delivered and is_nil(existing.delivered_at),
          do: Map.put(changes, :delivered_at, now()),
          else: changes
      end)

    existing |> Shipment.changeset(changes) |> Repo.update!()
  end

  defp next_shipment_status(:shipped, new), do: new
  defp next_shipment_status(:delivered, :returned), do: :returned
  defp next_shipment_status(current, _new), do: current

  defp shipped_at(%{"shipped_at" => unix}) when is_integer(unix),
    do: DateTime.from_unix!(unix)

  defp shipped_at(%{"ship_date" => date}) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> DateTime.new!(date, ~T[12:00:00], "Etc/UTC")
      _ -> nil
    end
  end

  defp shipped_at(_), do: nil

  ## Transitions

  # A parcel left the warehouse: the order is at least shipped, and the member
  # hears about this parcel (once).
  defp shipped(order, shipment) do
    advance(order, :shipped)

    if shipment.status == :shipped and is_nil(shipment.notified_at) and
         order.status not in [:failed, :canceled, :refunded] and
         ready_to_announce?(shipment) do
      notify_shipped(order, shipment)
    end

    :ok
  end

  # A parcel is announced once it can be tracked. Until then the next webhook
  # or poll gets another look; after the grace period it goes out regardless
  # (some services have no tracking), so the member is never left untold.
  defp ready_to_announce?(%Shipment{shipped_at: shipped_at} = shipment) do
    Shipment.trackable?(shipment) or is_nil(shipped_at) or
      DateTime.diff(now(), shipped_at) >= @tracking_grace_seconds
  end

  defp delivered(order, _shipment) do
    shipments =
      Repo.all(
        from(s in Shipment, where: s.order_id == ^order.id, select: s.status)
      )

    if shipments != [] and Enum.all?(shipments, &(&1 == :delivered)) do
      transition(order, :delivered, [:submitted, :in_production, :shipped],
        update: :delivered
      )
    end

    :ok
  end

  # The notification keys include the shipment id, so repeated "returned"
  # events for the same parcel never notify twice.
  defp returned(order, shipment) do
    reason =
      "Package #{shipment.tracking_number || shipment.printful_shipment_id} was returned to sender"

    notify_once(order, :returned, reason, shipment.id)
  end

  defp advance(order, target) do
    from_statuses =
      for {status, rank} <- @rank, rank < Map.fetch!(@rank, target), do: status

    transition(order, target, from_statuses, update: nil)
  end

  defp fail(order, kind, reason) when kind in [:failed, :canceled] do
    transition(order, kind, @before_shipment,
      update: kind,
      attention: {kind, reason},
      set: [failure_reason: String.slice(reason, 0, 255)]
    )

    :ok
  end

  defp hold(%Order{status: status} = order, reason)
       when status in @before_shipment do
    Notifications.alert_board(order, :on_hold, reason)
    :ok
  end

  defp hold(_order, _reason), do: :ok

  defp needs_approval(%Order{status: status} = order, reason)
       when status in @before_shipment do
    Notifications.alert_board(order, :needs_approval, reason)
    :ok
  end

  defp needs_approval(_order, _reason), do: :ok

  # One alert per refunded amount, so a repeated delivery of the same event
  # does not alert twice but a second, different refund does.
  defp refunded(order, amount) do
    text =
      case Amount.to_money(amount) do
        %Money{} = money -> Ysc.MoneyHelper.format_price(money)
        nil -> "an unknown amount"
      end

    Notifications.alert_board(
      order,
      :refunded,
      "Printful refunded #{text} to the club for this order.",
      refund_suffix(amount)
    )

    :ok
  end

  defp refund_suffix(amount) when is_binary(amount) or is_number(amount),
    do: to_string(amount)

  defp refund_suffix(_amount), do: nil

  # Moves `order` to `to` if it is currently in one of `from`, queueing the
  # member update and board alert in the same transaction. A no-op (status not
  # in `from`) changes and sends nothing.
  @dialyzer {:nowarn_function, transition: 4}
  defp transition(order, to, from, opts) do
    update_kind = Keyword.get(opts, :update)
    attention = Keyword.get(opts, :attention)
    extra = Keyword.get(opts, :set, [])
    now = now()

    Multi.new()
    |> Multi.run(:claim, fn repo, _ ->
      {count, _} =
        from(o in Order, where: o.id == ^order.id and o.status in ^from)
        |> repo.update_all(set: [status: to, updated_at: now] ++ extra)

      if count == 1, do: {:ok, :claimed}, else: {:error, :unchanged}
    end)
    |> then(fn multi ->
      if update_kind,
        do: Notifications.put_update_email(multi, order, update_kind),
        else: multi
    end)
    |> then(fn multi ->
      case attention do
        {kind, reason} ->
          Notifications.put_attention_email(multi, order, kind, reason)

        nil ->
          multi
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        if update_kind, do: Notifications.send_update_sms(order, update_kind)
        :changed

      {:error, :claim, :unchanged, _} ->
        :unchanged

      {:error, step, reason, _} ->
        raise "Could not record Printful update (#{step}): #{inspect(reason)}"
    end
  end

  @dialyzer {:nowarn_function, notify_shipped: 2}
  defp notify_shipped(order, shipment) do
    now = now()

    Multi.new()
    |> Multi.run(:claim, fn repo, _ ->
      {count, _} =
        from(s in Shipment,
          where: s.id == ^shipment.id and is_nil(s.notified_at)
        )
        |> repo.update_all(set: [notified_at: now, updated_at: now])

      if count == 1, do: {:ok, :claimed}, else: {:error, :already_notified}
    end)
    |> Notifications.put_shipped_email(order, shipment)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        Notifications.send_shipped_sms(order, shipment)
        :ok

      {:error, :claim, :already_notified, _} ->
        :ok

      {:error, step, reason, _} ->
        raise "Could not record shipment notification (#{step}): #{inspect(reason)}"
    end
  end

  # Update email + SMS + board alert for something that doesn't change the
  # order's status (a returned parcel), once per `suffix`.
  @dialyzer {:nowarn_function, notify_once: 4}
  defp notify_once(order, kind, reason, suffix) do
    Multi.new()
    |> Notifications.put_update_email(order, kind, suffix)
    |> Notifications.put_attention_email(order, kind, reason, suffix)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        Notifications.send_update_sms(order, kind, suffix)
        :ok

      {:error, step, reason, _} ->
        raise "Could not record return notification (#{step}): #{inspect(reason)}"
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc false
  def ci_query_explain_query do
    # The status-guarded claim behind every transition.
    from(o in Order,
      where:
        o.id == ^Ysc.Ci.QueryExplain.Fixtures.ulid() and
          o.status in ^@before_shipment
    )
  end
end
