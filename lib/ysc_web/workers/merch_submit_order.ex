defmodule YscWeb.Workers.MerchSubmitOrder do
  @moduledoc """
  Oban worker that submits a paid merch order to Printful.

  Transient failures (network, rate limits, Printful 5xx) are retried with
  backoff. A permanent rejection, or running out of attempts, marks the order
  `:failed` so it shows up for an admin instead of silently stalling.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 8,
    unique: [fields: [:args, :worker], keys: [:order_id], states: :incomplete]

  alias Ysc.Merch.{Fulfillment, Orders}
  alias Ysc.Printful.Error

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}} = job) do
    case Fulfillment.submit_to_printful(order_id) do
      :ok ->
        :ok

      {:error, %Error{} = error} ->
        handle_error(job, order_id, error)
    end
  end

  defp handle_error(job, order_id, error) do
    if Error.transient?(error) and job.attempt < job.max_attempts do
      {:error, error}
    else
      reason =
        if Error.transient?(error),
          do:
            "Printful was unreachable after #{job.max_attempts} attempts: #{error.message}",
          else: "Printful rejected the order: #{error.message}"

      case Orders.get_order(order_id) do
        nil -> :ok
        order -> Fulfillment.mark_failed(order, reason)
      end

      :ok
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # 30s, 1m, 2m, 4m ... capped at an hour.
    min(30 * Integer.pow(2, attempt - 1), 3_600)
  end
end
