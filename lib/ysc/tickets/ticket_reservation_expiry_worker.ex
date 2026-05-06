defmodule Ysc.Tickets.TicketReservationExpiryWorker do
  @moduledoc """
  Periodically cancels event ticket reservations past their `expires_at`.

  Rows become `status: \"cancelled\"` via `Ysc.Events.cancel_ticket_reservation/1`, so
  they disappear from admin hold lists and are excluded from checkout and capacity math.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Ysc.Logging

  alias Ysc.Events

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok,
     %{
       cancelled: cancelled,
       failed: failed,
       total_pending: total_pending,
       backlog_remaining: backlog_remaining
     }} =
      Events.expire_passed_ticket_reservations()

    if cancelled > 0 or failed > 0 or backlog_remaining > 0 do
      meta = [
        cancelled: cancelled,
        failed: failed,
        total_pending: total_pending,
        backlog_remaining: backlog_remaining
      ]

      if failed > 0 do
        Ysc.Logging.warning("Ticket reservation expiry batch finished", meta)
      else
        Ysc.Logging.info("Ticket reservation expiry batch finished", meta)
      end
    end

    {:ok,
     "Cancelled #{cancelled} expired ticket reservation(s) (#{failed} failed)"}
  end
end
