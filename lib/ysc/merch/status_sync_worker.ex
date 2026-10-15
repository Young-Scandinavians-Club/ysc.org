defmodule Ysc.Merch.StatusSyncWorker do
  @moduledoc """
  Safety net for missed Printful webhooks, run every 30 minutes: asks Printful
  about orders still in flight and applies what it says (status, shipments,
  cost) through the same code as the webhooks.

  Works through the least recently checked orders first, a bounded batch per
  run, to stay well inside Printful's API rate limit.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ysc.Merch.{Order, Orders, PrintfulEvents}
  alias Ysc.Printful.Error
  alias Ysc.Repo

  @in_flight [:submitted, :in_production, :shipped]
  # Orders older than this are given up on; whatever is wrong needs a human.
  @max_age_days 60
  @batch_size 40

  defp printful_client do
    Application.get_env(:ysc, :printful_client, Ysc.Printful.Client)
  end

  @impl Oban.Worker
  def perform(_job) do
    orders_to_check_query() |> Repo.all() |> Enum.each(&check/1)
    :ok
  end

  defp orders_to_check_query do
    cutoff = DateTime.add(DateTime.utc_now(), -@max_age_days * 86_400, :second)

    from(o in Order,
      where: o.status in ^@in_flight and not is_nil(o.printful_order_id),
      where: o.inserted_at > ^cutoff,
      order_by: [asc_nulls_first: o.printful_synced_at, asc: o.inserted_at],
      limit: ^@batch_size,
      select: o.id
    )
  end

  defp check(order_id) do
    with %Order{printful_order_id: printful_id} = order <-
           Orders.get_order(order_id),
         {:ok, printful_order} <- printful_client().get_order(printful_id) do
      PrintfulEvents.sync_order(order, printful_order)
    else
      nil ->
        :ok

      {:error, %Error{type: :not_found}} ->
        Ysc.Logging.warning("Printful no longer has a merch order we submitted",
          order_id: order_id
        )

      {:error, %Error{type: :rate_limited}} ->
        # Stop being a nuisance; the next run picks up where this left off.
        :ok

      {:error, %Error{} = error} ->
        Ysc.Logging.warning("Could not sync a merch order with Printful",
          order_id: order_id,
          error: Exception.message(error)
        )
    end
  end

  @doc false
  def ci_query_explain_query, do: orders_to_check_query()
end
