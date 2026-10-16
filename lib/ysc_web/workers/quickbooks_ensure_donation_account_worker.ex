defmodule YscWeb.Workers.QuickbooksEnsureDonationAccountWorker do
  @moduledoc """
  Creates the QuickBooks income account for a Stripe donation Payment Link.

  Enqueued from the `payment_link.created` and `payment_link.updated`
  webhooks so the account (named after the link's Stripe product) exists before
  the first donation arrives. Links that are not donation links are ignored.
  Booking and sync still create the account on demand if this job never ran.
  """

  require Ysc.Logging

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [
      period: 300,
      fields: [:args, :queue],
      states: :incomplete
    ]

  alias Ysc.Stripe.DonationPaymentLink

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_link_id" => payment_link_id}}) do
    case DonationPaymentLink.ensure_quickbooks_account(payment_link_id) do
      {:ok, account} ->
        Ysc.Logging.info("QuickBooks donation income account is ready",
          payment_link_id: payment_link_id,
          account: account
        )

        :ok

      :skip ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
