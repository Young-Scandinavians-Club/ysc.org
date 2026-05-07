defmodule Ysc.Bookings.BookingEntitlementExpiryWorker do
  @moduledoc """
  Periodically sets `status: :expired` on booking entitlements whose `expires_at`
  has passed so they no longer appear as active benefits or in admin outstanding lists.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Ysc.Logging

  alias Ysc.Bookings.Entitlements

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, %{expired: expired, failed: failed}} =
      Entitlements.expire_passed_entitlements()

    if expired > 0 or failed > 0 do
      Ysc.Logging.info("Booking entitlement expiry batch finished",
        expired: expired,
        failed: failed
      )
    end

    {:ok, "Expired #{expired} booking entitlement(s) (#{failed} failed)"}
  end
end
