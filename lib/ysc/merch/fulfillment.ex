defmodule Ysc.Merch.Fulfillment do
  @moduledoc """
  Turns a successful Stripe payment into a fulfilled merch order, and submits
  paid orders (member purchases and club-paid admin orders) to Printful.

  Every entry point is idempotent. Payment can be reported by the Stripe
  webhook, the member's return from checkout, and the stale-order sweep, in
  any order and more than once.
  """
  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ecto.Multi
  alias Ysc.Ledgers
  alias Ysc.Merch.{Cart, Notifications, Order, Orders, ShippingAddress}
  alias Ysc.MoneyHelper
  alias Ysc.Printful.Error
  alias Ysc.Repo
  alias YscWeb.Emails.{MerchOrderConfirmation, Notifier}
  alias YscWeb.Workers.MerchSubmitOrder

  defp stripe_client do
    Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
  end

  defp printful_client do
    Application.get_env(:ysc, :printful_client, Ysc.Printful.Client)
  end

  ## Payment

  @doc """
  Fulfills the order paid by a PaymentIntent (id or struct).

    * `{:ok, order}` - paid (now or previously); safe to show the receipt
    * `{:error, :not_succeeded}` - Stripe has not captured the payment yet
    * `{:error, :order_not_found | :amount_mismatch | :payment_intent_mismatch}`
  """
  @spec process_successful_payment(String.t() | Stripe.PaymentIntent.t()) ::
          {:ok, Order.t()} | {:error, atom() | term()}
  def process_successful_payment(payment_intent_id)
      when is_binary(payment_intent_id) do
    with {:ok, payment_intent} <-
           stripe_client().retrieve_payment_intent(payment_intent_id, %{}) do
      process_successful_payment(payment_intent)
    end
  end

  def process_successful_payment(%Stripe.PaymentIntent{} = payment_intent) do
    with {:ok, order} <- order_for(payment_intent),
         :ok <- validate(payment_intent, order) do
      # Anything past :pending was settled already (the claim, confirmation
      # email and submission job commit together), so there is nothing to
      # redo, and re-recording the payment would only re-trigger its side effects.
      if order.status == :pending do
        finalize(order, payment_intent)
      else
        {:ok, order}
      end
    end
  end

  defp order_for(payment_intent) do
    metadata = payment_intent.metadata || %{}

    order =
      case Map.get(metadata, "merch_order_id") ||
             Map.get(metadata, :merch_order_id) do
        id when is_binary(id) -> Orders.get_order(id)
        _ -> Orders.get_order_by_payment_intent(payment_intent.id)
      end

    case order do
      %Order{kind: :purchase} = order -> {:ok, order}
      _ -> {:error, :order_not_found}
    end
  end

  defp validate(payment_intent, order) do
    cond do
      payment_intent.status != "succeeded" ->
        {:error, :not_succeeded}

      payment_intent.amount != MoneyHelper.money_to_cents(order.total_amount) ->
        Ysc.Logging.error("Merch payment amount does not match the order",
          extra: %{
            order_id: order.id,
            payment_intent_id: payment_intent.id,
            paid_cents: payment_intent.amount
          }
        )

        {:error, :amount_mismatch}

      order.payment_intent_id && order.payment_intent_id != payment_intent.id ->
        Ysc.Logging.error("A second PaymentIntent was paid for a merch order",
          extra: %{
            order_id: order.id,
            expected: order.payment_intent_id,
            paid: payment_intent.id
          }
        )

        {:error, :payment_intent_mismatch}

      true ->
        :ok
    end
  end

  defp finalize(order, payment_intent) do
    with {:ok, payment} <- record_ledger_payment(order, payment_intent) do
      mark_paid(order, payment_intent, payment)
    end
  end

  defp record_ledger_payment(order, payment_intent) do
    fee =
      Ysc.Stripe.WebhookHandler.extract_stripe_fee_from_payment_intent(
        payment_intent
      )

    result =
      Ledgers.process_payment(%{
        user_id: order.user_id,
        amount: order.total_amount,
        entity_type: :merch,
        entity_id: order.id,
        external_payment_id: payment_intent.id,
        stripe_fee: fee,
        description: "Merch - Order #{order.reference_id}",
        property: nil,
        payment_method_id: nil
      })

    case result do
      {:ok, {payment, _transaction, _entries}} -> {:ok, payment}
      {:ok, payment} when is_struct(payment) -> {:ok, payment}
      {:error, reason} -> {:error, reason}
    end
  end

  # Flips pending -> paid together with the confirmation email and the Printful
  # submission job, so a paid order can never be left without either.
  @dialyzer {:nowarn_function, mark_paid: 3}
  defp mark_paid(order, payment_intent, payment) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.run(:claim, fn repo, _ ->
      {count, _} =
        from(o in Order, where: o.id == ^order.id and o.status == :pending)
        |> repo.update_all(
          set: [
            status: :paid,
            payment_id: payment.id,
            payment_intent_id: payment_intent.id,
            updated_at: now
          ]
        )

      if count == 1, do: {:ok, :claimed}, else: {:error, :already_processed}
    end)
    |> Notifier.schedule_email_multi(:confirmation_email, fn _ ->
      confirmation_email_attrs(Orders.get_order!(order.id))
    end)
    |> Oban.insert(:submit_job, MerchSubmitOrder.new(%{order_id: order.id}))
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        remove_ordered_variants_from_cart(order)
        {:ok, Orders.get_order!(order.id)}

      {:error, :claim, :already_processed, _} ->
        # Another process already claimed it. The claim, confirmation email and
        # submission job commit together, so there is nothing left to do.
        {:ok, Orders.get_order!(order.id)}

      {:error, step, reason, _} ->
        Ysc.Logging.error("Failed to mark merch order paid",
          extra: %{order_id: order.id, step: step, reason: inspect(reason)}
        )

        {:error, reason}
    end
  end

  @doc false
  def confirmation_email_attrs(%Order{} = order) do
    recipient = order.email || (order.user && order.user.email)

    %{
      recipient: recipient,
      idempotency_key: "merch_order_confirmation_#{order.id}",
      subject: MerchOrderConfirmation.get_subject(order),
      template: MerchOrderConfirmation.get_template_name(),
      variables: MerchOrderConfirmation.prepare_email_data(order),
      text_body: "",
      user_id: order.user_id
    }
  end

  defp remove_ordered_variants_from_cart(%Order{user: %{} = user} = order) do
    Enum.each(order.items, &Cart.remove(user, &1.variant_id))
  end

  defp remove_ordered_variants_from_cart(_), do: :ok

  ## Printful submission

  @doc """
  Sends a paid order to Printful and confirms it, which makes Printful bill
  the club's card on file.

  Returns `:ok` when submitted (or when there is nothing to do), `{:error,
  %Ysc.Printful.Error{}}` for a failure worth retrying, and `{:failed,
  reason}` once the order has been marked failed.
  """
  @spec submit_to_printful(String.t()) ::
          :ok | {:error, Error.t()} | {:failed, String.t()}
  def submit_to_printful(order_id) do
    case Orders.get_order(order_id) do
      nil ->
        :ok

      %Order{status: status} = order when status in [:paid, :submitting] ->
        order |> begin_submission() |> do_submit()

      %Order{} ->
        :ok
    end
  end

  defp begin_submission(%Order{status: :paid} = order) do
    from(o in Order, where: o.id == ^order.id and o.status == :paid)
    |> Repo.update_all(set: [status: :submitting, updated_at: now()])

    %{order | status: :submitting}
  end

  defp begin_submission(order), do: order

  defp do_submit(order) do
    # Printful's external_id makes this safe to retry: if an earlier attempt
    # created the order but we never saw the response, we adopt it.
    case printful_client().get_order_by_external_id(order.reference_id) do
      {:ok, existing} when is_map(existing) ->
        record_submission(order, existing)

      {:error, %Error{type: :not_found}} ->
        create_in_printful(order)

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp create_in_printful(order) do
    case printful_client().create_order(printful_payload(order), true) do
      {:ok, %{"status" => "draft", "id" => id}} ->
        # Created but not confirmed (e.g. costs were still calculating).
        case printful_client().confirm_order(id) do
          {:ok, confirmed} -> record_submission(order, confirmed)
          {:error, %Error{} = error} -> {:error, error}
        end

      {:ok, created} ->
        record_submission(order, created)

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  @doc false
  def printful_payload(%Order{} = order) do
    %{
      external_id: order.reference_id,
      shipping: order.shipping_method || "STANDARD",
      recipient:
        order |> ShippingAddress.from_order() |> ShippingAddress.to_recipient(),
      items:
        Enum.map(order.items, fn item ->
          %{
            sync_variant_id: item.variant.printful_sync_variant_id,
            quantity: item.quantity
          }
        end)
    }
  end

  # A Printful webhook can beat our own response, advancing the order past
  # :submitting. Recording the Printful id and submission time must still
  # happen, so only the status flip is guarded.
  defp record_submission(order, printful_order) do
    cost = printful_total(printful_order)

    identity =
      [
        printful_order_id: printful_order["id"],
        submitted_at: now(),
        updated_at: now()
      ]
      |> then(fn changes ->
        if cost, do: Keyword.put(changes, :printful_cost, cost), else: changes
      end)

    from(o in Order, where: o.id == ^order.id and is_nil(o.printful_order_id))
    |> Repo.update_all(set: identity)

    from(o in Order,
      where: o.id == ^order.id and o.status in [:paid, :submitting]
    )
    |> Repo.update_all(set: [status: :submitted, updated_at: now()])

    :ok
  end

  defp printful_total(%{"costs" => %{"total" => total}})
       when is_binary(total) do
    case MoneyHelper.parse_money(total) do
      %Money{} = money -> if Money.positive?(money), do: money
      _ -> nil
    end
  end

  defp printful_total(_), do: nil

  @doc """
  Marks an unsubmitted order failed, with a reason an admin can read, and
  tells the member and the board. Only orders that have not reached Printful
  are touched.
  """
  @spec mark_failed(Order.t(), String.t()) :: :ok
  @dialyzer {:nowarn_function, mark_failed: 2}
  def mark_failed(%Order{} = order, reason) do
    # Fresh copy, with the member and items the emails need.
    order = Orders.get_order(order.id) || order

    Multi.new()
    |> Multi.run(:claim, fn repo, _ ->
      {count, _} =
        from(o in Order,
          where: o.id == ^order.id and o.status in [:paid, :submitting]
        )
        |> repo.update_all(
          set: [
            status: :failed,
            failure_reason: String.slice(reason, 0, 255),
            updated_at: now()
          ]
        )

      if count == 1, do: {:ok, :claimed}, else: {:error, :unchanged}
    end)
    |> Notifications.put_update_email(order, :failed)
    |> Notifications.put_attention_email(order, :submit_failed, reason)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        Notifications.send_update_sms(order, :failed)

        Ysc.Logging.error("Merch order could not be submitted to Printful",
          extra: %{
            order_id: order.id,
            reference_id: order.reference_id,
            kind: order.kind,
            reason: reason
          }
        )

        :ok

      {:error, :claim, :unchanged, _} ->
        :ok

      {:error, step, error, _} ->
        Ysc.Logging.error("Could not record a failed merch order",
          extra: %{order_id: order.id, step: step, reason: inspect(error)}
        )

        :ok
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc false
  def ci_query_explain_query do
    # The status-guarded claim used when a payment is recorded.
    from(o in Order,
      where:
        o.id == ^Ysc.Ci.QueryExplain.Fixtures.ulid() and o.status == :pending
    )
  end
end
