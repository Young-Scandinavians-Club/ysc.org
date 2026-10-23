defmodule Ysc.Merch.AdminOrders do
  @moduledoc """
  What admins do with merch orders: place club-paid ("free") orders, find the
  ones that need attention, and retry a failed submission.

  A club-paid order never touches Stripe or the ledger. The member (or custom
  recipient) pays nothing, Printful bills the club's own card once it accepts
  the order, and the cost is tracked on the order (`Ysc.Merch.Order.cost/1`)
  and, when the order is linked to an event, on that event's cost dashboard.
  """
  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ecto.Multi
  alias Ysc.Accounts.User
  alias Ysc.Ledgers.Refund

  alias Ysc.Merch.{
    Fulfillment,
    Order,
    OrderItem,
    Orders,
    Shipping,
    ShippingAddress
  }

  alias Ysc.Printful.{Amount, Error}
  alias Ysc.Repo

  alias YscWeb.Emails.{MerchAdminOrderBoardNotification, Notifier}
  alias YscWeb.Workers.MerchSubmitOrder

  @page_size 25
  @estimate_attempts 3
  @estimate_wait_ms 600

  # List cards: who it's for, item names, money, status. Skip address / PI
  # ids / Printful payload and a JOIN that would SELECT users.*.
  @list_order_fields [
    :id,
    :reference_id,
    :kind,
    :status,
    :recipient_name,
    :total_amount,
    :printful_cost,
    :estimated_cost,
    :inserted_at,
    :user_id
  ]
  @list_user_fields [:id, :first_name, :last_name]
  @list_item_fields [:id, :order_id, :name, :quantity]

  defp printful_client do
    Application.get_env(:ysc, :printful_client, Ysc.Printful.Client)
  end

  ## Listing

  @type filter :: :all | :needs_attention | :club_paid | :purchases

  @doc "The filters the orders list offers, in display order."
  def filters, do: [:all, :needs_attention, :club_paid, :purchases]

  @doc """
  One page of orders, newest first, with recipient name and item names loaded.

  `search` matches the order number, recipient name or email, purpose, the
  member's name or email, and item names. `params` are Flop's (`"page"`,
  `"page_size"`). Search uses `EXISTS` so a `JOIN users` cannot `SELECT *`.

  Member purchases are only listed once paid, so abandoned checkouts do not
  clutter the list. Detail pages still use `Orders.get_order/1`.
  """
  @spec paginate_orders(filter(), String.t() | nil, map()) ::
          {:ok, {[Order.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def paginate_orders(filter \\ :all, search \\ nil, params \\ %{}) do
    filter
    |> base_query()
    |> apply_search(search)
    |> with_list_preloads()
    |> run_page(params)
  end

  @doc "One page of the orders a member received, newest first."
  def paginate_for_user(user_id, params \\ %{}) do
    :all
    |> base_query()
    |> where([o], o.user_id == ^user_id)
    |> with_list_preloads()
    |> run_page(params)
  end

  defp with_list_preloads(query) do
    from(o in query,
      select: struct(o, ^@list_order_fields),
      preload: [
        user: ^list_user_query(),
        items: ^list_item_query()
      ]
    )
  end

  defp list_user_query do
    from(u in User, select: struct(u, ^@list_user_fields))
  end

  defp list_item_query do
    from(i in OrderItem, select: struct(i, ^@list_item_fields))
  end

  defp run_page(query, params) do
    Flop.validate_and_run(query, Map.take(params, ["page", "page_size"]),
      for: Order
    )
  end

  defp apply_search(query, term) when term in [nil, ""], do: query

  defp apply_search(query, term) do
    pattern = like_pattern(String.trim(term))

    where(
      query,
      [o],
      ilike(o.reference_id, ^pattern) or
        ilike(o.recipient_name, ^pattern) or
        ilike(o.email, ^pattern) or
        ilike(o.purpose, ^pattern) or
        exists(
          from(u in User,
            where: u.id == parent_as(:order).user_id,
            where:
              ilike(u.first_name, ^pattern) or
                ilike(u.last_name, ^pattern) or
                ilike(
                  fragment("concat(?, ' ', ?)", u.first_name, u.last_name),
                  ^pattern
                ) or
                ilike(fragment("(?::text)", u.email), ^pattern),
            select: 1
          )
        ) or
        exists(
          from(i in OrderItem,
            where:
              i.order_id == parent_as(:order).id and ilike(i.name, ^pattern),
            select: 1
          )
        )
    )
  end

  # What was typed is text to find, not a pattern.
  defp like_pattern(term),
    do: "%" <> String.replace(term, ~r/[\\%_]/, &("\\" <> &1)) <> "%"

  @doc "How many orders are failed and waiting for an admin."
  def needs_attention_count do
    :needs_attention |> base_query() |> select([o], count(o.id)) |> Repo.one()
  end

  defp base_query(filter) do
    visible =
      from(o in Order,
        as: :order,
        where: o.kind == :admin_comp or not is_nil(o.payment_id)
      )

    case filter do
      :needs_attention -> where(visible, [o], o.status == :failed)
      :club_paid -> where(visible, [o], o.kind == :admin_comp)
      :purchases -> where(visible, [o], o.kind == :purchase)
      _ -> visible
    end
  end

  ## Order form helpers

  @doc """
  What can be ordered: products with at least one available variant, as
  `[{product, [variant]}]`. Hidden products are included, so an admin can
  order something that is not on sale to members.
  """
  def orderable_products do
    Ysc.Merch.list_orderable_products()
  end

  @doc """
  Resolves `[%{variant_id, quantity}]` from the form into order lines.

  `{:error, :no_items}`, `{:error, :invalid_quantity}` or
  `{:error, :unavailable_variant}` when the selection cannot be ordered.
  """
  def resolve_lines(selections) when is_list(selections) do
    selections = Enum.reject(selections, &(&1.variant_id in [nil, ""]))

    cond do
      selections == [] ->
        {:error, :no_items}

      Enum.any?(selections, &(not valid_quantity?(&1.quantity))) ->
        {:error, :invalid_quantity}

      true ->
        variants =
          from(v in Ysc.Merch.Variant,
            where: v.id in ^Enum.map(selections, & &1.variant_id),
            where: v.available == true,
            preload: [:product]
          )
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        lines =
          for %{variant_id: id, quantity: quantity} <- selections,
              variant = Map.get(variants, id),
              do: %{variant: variant, quantity: quantity}

        if length(lines) == length(selections),
          do: {:ok, merge_duplicate_lines(lines)},
          else: {:error, :unavailable_variant}
    end
  end

  defp valid_quantity?(quantity),
    do: is_integer(quantity) and quantity in 1..500

  # The same variant picked twice becomes one line.
  defp merge_duplicate_lines(lines) do
    lines
    |> Enum.group_by(& &1.variant.id)
    |> Enum.map(fn {_id, [first | _] = same} ->
      %{first | quantity: same |> Enum.map(& &1.quantity) |> Enum.sum()}
    end)
    |> Enum.sort_by(& &1.variant.name)
  end

  ## Estimate

  @doc """
  Everything the review step needs: Printful's shipping options for the
  address and items (cheapest picked) and what that would cost the club.

  Errors are those of `Ysc.Merch.Shipping.options/2`: `{:rejected, message}`
  when Printful will not ship this, `:unavailable` when it cannot say.
  """
  def review(%ShippingAddress{} = address, lines) do
    with {:ok, [option | _] = options} <- Shipping.options(address, lines) do
      {:ok,
       %{
         options: options,
         option: option,
         estimate: estimate_cost(address, lines, option.id)
       }}
    end
  end

  @type estimate :: %{total: Money.t(), shipping: Money.t() | nil}

  @doc """
  Asks Printful what the order would cost the club (items, shipping, tax) for
  the chosen shipping option.

  `{:error, :unavailable}` when Printful cannot say right now; the order can
  still be placed, it just has no estimate until Printful reports the cost.
  """
  @spec estimate_cost(ShippingAddress.t(), [map()], String.t()) ::
          {:ok, estimate()} | {:error, :unavailable}
  def estimate_cost(%ShippingAddress{} = address, lines, shipping_id) do
    payload = %{
      shipping: shipping_id,
      recipient: ShippingAddress.to_recipient(address),
      items:
        Enum.map(lines, fn %{variant: variant, quantity: quantity} ->
          %{
            sync_variant_id: variant.printful_sync_variant_id,
            quantity: quantity
          }
        end)
    }

    do_estimate(payload, @estimate_attempts)
  end

  defp do_estimate(payload, attempts_left) do
    case printful_client().estimate_costs(payload) do
      {:ok, %{"costs" => %{"calculation_status" => "calculating"}}}
      when attempts_left > 1 ->
        Process.sleep(estimate_wait_ms())
        do_estimate(payload, attempts_left - 1)

      {:ok, %{"costs" => %{"calculation_status" => status}}}
      when status in ["calculating", "failed"] ->
        {:error, :unavailable}

      {:ok, %{"costs" => %{"total" => total} = costs}} ->
        case parse_money(total) do
          %Money{} = money ->
            {:ok, %{total: money, shipping: parse_money(costs["shipping"])}}

          nil ->
            {:error, :unavailable}
        end

      {:ok, _} ->
        {:error, :unavailable}

      {:error, %Error{} = error} ->
        Ysc.Logging.warning("Printful cost estimate unavailable",
          type: error.type,
          message: error.message
        )

        {:error, :unavailable}
    end
  end

  defp estimate_wait_ms do
    Application.get_env(:ysc, :printful_estimate_wait_ms, @estimate_wait_ms)
  end

  defp parse_money(value), do: Amount.to_money(value)

  ## Placing an order

  @doc """
  Places a club-paid order.

  `params`:

    * `:address` - a validated `Ysc.Merch.ShippingAddress`
    * `:lines` - from `resolve_lines/1`
    * `:option` - the chosen shipping option (`Ysc.Merch.Shipping.options/2`)
    * `:purpose` - why the club is paying (required)
    * `:user_id` - the member receiving it, if any
    * `:event_id` - the event it is for, if any
    * `:estimated_cost` - from `estimate_cost/3`, if available

  In one transaction this creates the order, queues the Printful submission,
  emails the recipient their confirmation, and emails the board a summary
  that names `admin`. Only full admins may place orders.

  Errors: `:not_authorized`, `:no_items`, `:failed` (something unexpected;
  nothing was created or sent), or an `Ecto.Changeset`.
  """
  @spec create_comp_order(User.t(), map()) ::
          {:ok, Order.t()}
          | {:error, :not_authorized | :no_items | :failed | Ecto.Changeset.t()}
  def create_comp_order(%User{role: :admin} = admin, params) do
    lines = Map.fetch!(params, :lines)

    if lines == [] do
      {:error, :no_items}
    else
      insert_comp_order(admin, params, lines)
    end
  end

  def create_comp_order(%User{}, _params), do: {:error, :not_authorized}

  # Dialyzer false positive on Ecto.Multi pipelines (same as elsewhere in the app).
  @dialyzer {:nowarn_function, insert_comp_order: 3}
  defp insert_comp_order(admin, params, lines) do
    attrs =
      params.address
      |> ShippingAddress.to_order_attrs()
      |> Map.merge(%{
        user_id: Map.get(params, :user_id),
        event_id: Map.get(params, :event_id),
        purpose: Map.get(params, :purpose),
        shipping_method: params.option.id,
        delivery_estimate_min: Map.get(params.option, :min_date),
        delivery_estimate_max: Map.get(params.option, :max_date),
        estimated_cost: Map.get(params, :estimated_cost)
      })

    Multi.new()
    |> Multi.run(:order, fn repo, _ ->
      %Order{}
      |> Order.admin_comp_changeset(attrs, admin.id)
      |> repo.insert_with_reference_retry(Order)
    end)
    |> Multi.run(:items, fn repo, %{order: order} ->
      insert_items(repo, order, lines)
    end)
    |> Multi.run(:email_order, fn _repo, %{order: order} ->
      {:ok, Orders.get_order_for_email!(order.id)}
    end)
    |> put_confirmation_email()
    |> Notifier.schedule_email_multi(:board_email, fn %{email_order: order} ->
      board_email_attrs(order)
    end)
    |> Oban.insert(:submit_job, fn %{order: order} ->
      MerchSubmitOrder.new(%{order_id: order.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} ->
        {:ok, Orders.get_order!(order.id)}

      {:error, _step, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, step, reason, _} ->
        Ysc.Logging.error("Could not place a club-paid merch order",
          extra: %{step: step, reason: inspect(reason), admin_id: admin.id}
        )

        {:error, :failed}
    end
  end

  defp insert_items(repo, order, lines) do
    Enum.reduce_while(lines, {:ok, []}, fn %{variant: variant, quantity: q},
                                           {:ok, acc} ->
      %OrderItem{order_id: order.id}
      |> OrderItem.changeset(%{
        variant_id: variant.id,
        quantity: q,
        name: item_name(variant),
        unit_price: variant.retail_price
      })
      |> repo.insert()
      |> case do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp item_name(%{name: name}) when name not in [nil, ""], do: name

  defp item_name(variant),
    do: variant |> Repo.preload(:product) |> then(& &1.product.name)

  # The recipient is told about the order when we have somewhere to send it.
  defp put_confirmation_email(multi) do
    Multi.merge(multi, fn %{email_order: order} ->
      attrs = Fulfillment.confirmation_email_attrs(order)

      if attrs.recipient in [nil, ""] do
        Multi.new()
      else
        Notifier.schedule_email_multi(Multi.new(), :confirmation_email, attrs)
      end
    end)
  end

  @doc false
  def board_email_attrs(%Order{} = order) do
    %{
      recipient: Ysc.EmailConfig.board_email(),
      idempotency_key: "merch_admin_order_board_#{order.id}",
      subject: MerchAdminOrderBoardNotification.get_subject(order),
      template: MerchAdminOrderBoardNotification.get_template_name(),
      variables: MerchAdminOrderBoardNotification.prepare_email_data(order),
      text_body: "",
      user_id: nil
    }
  end

  ## Retrying

  @doc """
  Sends a failed order to Printful again.

  Refused when Printful already has the order (`:already_submitted`), when the
  order is not failed (`:not_failed`), or when a member's payment for it has
  been refunded (`:refunded`), so a refunded order cannot ship by mistake.
  """
  @spec retry_submission(Order.t()) ::
          :ok | {:error, :not_failed | :already_submitted | :refunded}
  @dialyzer {:nowarn_function, retry_submission: 1}
  def retry_submission(%Order{status: :failed, printful_order_id: id})
      when not is_nil(id),
      do: {:error, :already_submitted}

  def retry_submission(%Order{status: :failed} = order) do
    if refunded?(order) do
      {:error, :refunded}
    else
      Multi.new()
      |> Multi.run(:claim, fn repo, _ ->
        {count, _} =
          from(o in Order, where: o.id == ^order.id and o.status == :failed)
          |> repo.update_all(
            set: [
              status: :submitting,
              failure_reason: nil,
              updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
            ]
          )

        if count == 1, do: {:ok, :claimed}, else: {:error, :not_failed}
      end)
      |> Oban.insert(:submit_job, MerchSubmitOrder.new(%{order_id: order.id}))
      |> Repo.transaction()
      |> case do
        {:ok, _} -> :ok
        {:error, :claim, :not_failed, _} -> {:error, :not_failed}
      end
    end
  end

  def retry_submission(%Order{}), do: {:error, :not_failed}

  defp refunded?(%Order{payment_id: nil}), do: false

  defp refunded?(%Order{payment_id: payment_id}) do
    Repo.exists?(from(r in Refund, where: r.payment_id == ^payment_id))
  end

  @doc false
  def ci_query_explain_query do
    :needs_attention
    |> base_query()
    |> apply_search("a")
    |> with_list_preloads()
    |> order_by([o], desc: o.inserted_at)
    |> limit(^@page_size)
  end
end
