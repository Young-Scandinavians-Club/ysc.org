defmodule Ysc.VerificationCodeCleanupWorker do
  @moduledoc """
  Periodically deletes expired email/SMS verification codes from Postgres.

  Codes expire after ~10 minutes but unused rows would otherwise linger until
  lazily touched. This worker sweeps them on a schedule.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Ysc.Logging

  alias Ysc.VerificationCache

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case VerificationCache.cleanup_expired() do
      {:ok, 0} ->
        :ok

      {:ok, count} when is_integer(count) and count > 0 ->
        Ysc.Logging.info("Deleted expired verification codes",
          deleted_count: count
        )

        :ok
    end
  end
end
