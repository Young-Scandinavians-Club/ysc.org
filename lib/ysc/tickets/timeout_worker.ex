defmodule Ysc.Tickets.TimeoutWorker do
  @moduledoc """
  Background worker for handling ticket order timeouts.

  This worker runs periodically to:
  - Find ticket orders that have exceeded the 30-minute payment timeout
  - Expire those orders and release the reserved tickets
  - Clean up expired orders
  """

  use Oban.Worker, queue: :tickets, max_attempts: 3

  import Ecto.Query
  require Logger

  alias Ysc.Tickets

  # Maximum number of orders to process in a single batch
  @batch_size 100
  # Maximum number of orders to process per job run
  @max_orders_per_run 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "schedule_next"}}) do
    # This job schedules the next timeout check and then schedules itself again
    {expired_count, failed_count} = expire_timed_out_orders()
    Ysc.Tickets.Scheduler.schedule_next_timeout_check()

    {:ok,
     "Expired #{expired_count} timed out ticket orders (#{failed_count} failed) and scheduled next check"}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_order_id" => ticket_order_id}}) do
    # Handle individual order timeout
    case expire_specific_order(ticket_order_id) do
      :ok ->
        {:ok, "Expired specific ticket order"}

      {:error, reason} ->
        # Return error to trigger retry
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {expired_count, failed_count} = expire_timed_out_orders()

    {:ok,
     "Expired #{expired_count} timed out ticket orders (#{failed_count} failed)"}
  end

  @doc """
  Expires a specific ticket order by ID.

  Uses row-level locking to prevent race conditions where the order might
  be processed concurrently (e.g., payment completing at the same time).

  Returns:
  - `:ok` if the order was expired or already processed
  - `{:error, reason}` if expiration failed and should be retried
  """
  def expire_specific_order(ticket_order_id) do
    # Use a transaction with row-level locking to prevent race conditions
    result =
      Ysc.Repo.transaction(fn ->
        # Lock the row for update to prevent concurrent modifications
        case Ysc.Repo.one(
               from to in Ysc.Tickets.TicketOrder,
                 where: to.id == ^ticket_order_id,
                 lock: "FOR UPDATE NOWAIT"
             ) do
          nil ->
            Logger.warning("Ticket order not found for expiration",
              ticket_order_id: ticket_order_id
            )

            :not_found

          ticket_order ->
            # Double-check status after acquiring lock
            if ticket_order.status == :pending do
              # Preload tickets before expiring
              ticket_order_with_tickets =
                Ysc.Repo.preload(ticket_order, :tickets)

              case Tickets.expire_ticket_order(ticket_order_with_tickets) do
                {:ok, _expired_order} ->
                  Logger.info("Expired specific ticket order due to timeout",
                    ticket_order_id: ticket_order.id,
                    reference_id: ticket_order.reference_id,
                    user_id: ticket_order.user_id
                  )

                  :expired

                {:error, reason} ->
                  Logger.error("Failed to expire specific ticket order",
                    ticket_order_id: ticket_order.id,
                    reference_id: ticket_order.reference_id,
                    error: reason
                  )

                  # Return error to trigger retry
                  Ysc.Repo.rollback({:error, reason})
              end
            else
              Logger.info("Ticket order already processed, skipping expiration",
                ticket_order_id: ticket_order.id,
                status: ticket_order.status
              )

              :already_processed
            end
        end
      end)

    case result do
      {:ok, :expired} -> :ok
      {:ok, :already_processed} -> :ok
      {:ok, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Manually trigger expiration of timed out orders.
  This can be called from a cron job or scheduled task.

  Uses batching to prevent memory issues and row-level locking to prevent
  concurrent processing of the same orders.

  Note: expires_at is already set to (now + timeout) when the order is created,
  so we just need to check if expires_at < now (not now - timeout).

  Returns: `{expired_count, failed_count}` tuple
  """
  def expire_timed_out_orders do
    now = DateTime.utc_now()
    expire_timed_out_orders_batched(now, 0, 0, 0)
  end

  defp expire_timed_out_orders_batched(
         _now,
         offset,
         expired_count,
         failed_count
       )
       when offset >= @max_orders_per_run do
    Logger.info("Reached maximum orders per run limit",
      max_orders: @max_orders_per_run,
      expired_count: expired_count,
      failed_count: failed_count
    )

    {expired_count, failed_count}
  end

  defp expire_timed_out_orders_batched(now, offset, expired_count, failed_count) do
    # Fetch a batch of expired orders with row-level locking
    # Using FOR UPDATE SKIP LOCKED to prevent concurrent workers from processing the same orders
    expired_orders =
      Ysc.Tickets.TicketOrder
      |> where([t], t.status == :pending and t.expires_at < ^now)
      |> order_by([t], asc: t.expires_at)
      |> limit(^@batch_size)
      |> offset(^offset)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> preload(:tickets)
      |> Ysc.Repo.all()

    if Enum.empty?(expired_orders) do
      Logger.info("Completed expiration batch processing",
        total_expired: expired_count,
        total_failed: failed_count
      )

      {expired_count, failed_count}
    else
      Logger.info("Processing expiration batch",
        batch_size: length(expired_orders),
        offset: offset,
        total_processed: expired_count + failed_count
      )

      # Process each order and track results
      {batch_expired, batch_failed} =
        Enum.reduce(expired_orders, {0, 0}, fn ticket_order,
                                               {acc_expired, acc_failed} ->
          case Tickets.expire_ticket_order(ticket_order) do
            {:ok, _expired_order} ->
              Logger.info("Expired ticket order due to timeout",
                ticket_order_id: ticket_order.id,
                reference_id: ticket_order.reference_id,
                user_id: ticket_order.user_id
              )

              {acc_expired + 1, acc_failed}

            {:error, reason} ->
              Logger.error("Failed to expire ticket order",
                ticket_order_id: ticket_order.id,
                reference_id: ticket_order.reference_id,
                error: reason
              )

              {acc_expired, acc_failed + 1}
          end
        end)

      # Continue with next batch
      expire_timed_out_orders_batched(
        now,
        offset + @batch_size,
        expired_count + batch_expired,
        failed_count + batch_failed
      )
    end
  end

  @doc """
  Schedules a timeout check job to run every 5 minutes.
  """
  def schedule_timeout_check do
    %{}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Schedules a one-time timeout check for a specific ticket order.

  If the order has already expired (negative delay), it will be expired immediately
  by scheduling a job to run as soon as possible.
  """
  def schedule_order_timeout(ticket_order_id, expires_at) do
    # Calculate delay until expiration
    delay_seconds = DateTime.diff(expires_at, DateTime.utc_now(), :second)

    cond do
      delay_seconds > 0 ->
        # Schedule for future expiration
        %{ticket_order_id: ticket_order_id}
        |> new(schedule_in: delay_seconds)
        |> Oban.insert()

      delay_seconds <= 0 ->
        # Order has already expired, schedule immediate expiration
        Logger.warning("Order already expired, scheduling immediate expiration",
          ticket_order_id: ticket_order_id,
          expires_at: expires_at,
          delay_seconds: delay_seconds
        )

        %{ticket_order_id: ticket_order_id}
        |> new()
        |> Oban.insert()
    end
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Job timeout after 30 seconds
    30_000
  end
end
