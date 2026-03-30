defmodule Ysc.GoogleWallet.MembershipUpdateWorker do
  @moduledoc """
  Oban worker that updates a Google Wallet membership pass after a subscription renewal.

  Enqueued inside the `customer.subscription.updated` webhook transaction so the
  job only becomes visible to the Oban queue once the outer `Repo.transaction` in
  `process_webhook_event/2` has successfully committed. This guarantees that the
  Google Wallet PATCH never runs against a DB state that was subsequently rolled
  back (e.g. if marking the webhook event as processed fails).
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Ysc.Logging

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "period_end" => period_end_iso}
      }) do
    wallet_attrs = %{
      "validTimeInterval" => %{
        "end" => %{"date" => period_end_iso}
      }
    }

    case Ysc.GoogleWallet.update_membership_object(user_id, wallet_attrs) do
      :ok ->
        Ysc.Logging.info(
          "Google Wallet membership pass updated after subscription renewal",
          user_id: user_id
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.warning(
          "Google Wallet membership update failed after subscription renewal",
          user_id: user_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end
end
