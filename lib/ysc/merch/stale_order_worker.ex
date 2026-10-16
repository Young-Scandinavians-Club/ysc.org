defmodule Ysc.Merch.StaleOrderWorker do
  @moduledoc """
  Safety net for merch checkouts, run every 15 minutes.

    * A pending order whose PaymentIntent has since succeeded (a missed or
      delayed webhook, or a member who closed the tab after paying) is
      fulfilled.
    * A pending order abandoned for more than 24 hours is canceled, and its
      PaymentIntent canceled so it can't be paid later against a stale order.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ysc.Merch.{Fulfillment, Order, Orders, StripeService}
  alias Ysc.Repo

  @check_after_minutes 10
  @abandon_after_hours 24
  @batch_size 50

  defp stripe_client do
    Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
  end

  @impl Oban.Worker
  def perform(_job) do
    pending_orders_query()
    |> Repo.all()
    |> Enum.each(&check/1)

    :ok
  end

  defp pending_orders_query do
    cutoff =
      DateTime.add(DateTime.utc_now(), -@check_after_minutes * 60, :second)

    from(o in Order,
      where:
        o.kind == :purchase and o.status == :pending and o.inserted_at < ^cutoff,
      order_by: [asc: o.inserted_at],
      limit: ^@batch_size
    )
  end

  defp check(%Order{payment_intent_id: nil} = order) do
    if abandoned?(order), do: Orders.cancel_pending(order, "Abandoned checkout")
  end

  defp check(%Order{payment_intent_id: payment_intent_id} = order) do
    case stripe_client().retrieve_payment_intent(payment_intent_id, %{}) do
      {:ok, %{status: "succeeded"} = intent} ->
        fulfil(order, intent)

      {:ok, %{status: "canceled"}} ->
        Orders.cancel_pending(order, "Payment canceled")

      {:ok, _open_intent} ->
        if abandoned?(order), do: abandon(order)

      {:error, reason} ->
        Ysc.Logging.warning("Could not check merch PaymentIntent",
          order_id: order.id,
          error: inspect(reason)
        )
    end
  end

  defp fulfil(order, intent) do
    case Fulfillment.process_successful_payment(intent) do
      {:ok, _} ->
        Ysc.Logging.info("Recovered a merch payment missed by webhook",
          order_id: order.id,
          reference_id: order.reference_id
        )

      {:error, reason} ->
        Ysc.Logging.error(
          "Merch payment succeeded but the order could not be fulfilled",
          extra: %{order_id: order.id, reason: inspect(reason)}
        )
    end
  end

  defp abandon(order) do
    case StripeService.cancel_payment_intent(order.payment_intent_id) do
      {:ok, :canceled} ->
        Orders.cancel_pending(order, "Abandoned checkout")

      {:ok, :succeeded} ->
        # Paid in the instant before we canceled; fulfil instead.
        with {:ok, intent} <-
               stripe_client().retrieve_payment_intent(
                 order.payment_intent_id,
                 %{}
               ) do
          fulfil(order, intent)
        end

      {:error, reason} ->
        Ysc.Logging.warning("Could not cancel abandoned merch PaymentIntent",
          order_id: order.id,
          error: inspect(reason)
        )
    end
  end

  defp abandoned?(order) do
    DateTime.diff(DateTime.utc_now(), order.inserted_at, :hour) >=
      @abandon_after_hours
  end

  @doc false
  def ci_query_explain_query, do: pending_orders_query()
end
