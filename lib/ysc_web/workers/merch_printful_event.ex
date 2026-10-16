defmodule YscWeb.Workers.MerchPrintfulEvent do
  @moduledoc """
  Oban worker that applies one Printful webhook event to our records.

  The webhook controller only validates and enqueues, so Printful gets a fast
  200 and a transient failure on our side is retried instead of lost. The
  event handling is idempotent (see `Ysc.Merch.PrintfulEvents`), so a retry or
  a duplicate delivery is harmless.
  """
  use Oban.Worker, queue: :default, max_attempts: 10

  alias Ysc.Merch.PrintfulEvents

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type, "data" => data}}) do
    PrintfulEvents.handle_event(type, data)
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}),
    do: min(15 * Integer.pow(2, attempt - 1), 1_800)
end
