defmodule Ysc.Bookings.ModificationHoldExpiryWorker do
  @moduledoc """
  Releases expired modification payment holds on completed bookings.

  When a member starts paying for a booking modification, inventory for newly
  selected dates is held briefly. This worker clears holds that were not
  completed before `modification_hold_expires_at`.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  require Ysc.Logging

  alias Ysc.Bookings.{Booking, BookingLocker}
  alias Ysc.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    expire_expired_modification_holds()
    {:ok, "Expired expired modification holds"}
  end

  @doc """
  Releases modification holds that have passed their expiry time.
  """
  def expire_expired_modification_holds do
    now = DateTime.utc_now()

    expired_bookings =
      Booking
      |> where(
        [b],
        b.status == :complete and not is_nil(b.modification_hold_expires_at) and
          b.modification_hold_expires_at < ^now
      )
      |> Repo.all()

    count = length(expired_bookings)

    Enum.each(expired_bookings, fn booking ->
      case BookingLocker.release_modification_hold(booking.id,
             clear_attrs: false
           ) do
        {:ok, _} ->
          Ysc.Logging.info("Expired modification hold due to timeout",
            booking_id: booking.id,
            reference_id: booking.reference_id,
            user_id: booking.user_id
          )

          :telemetry.execute(
            [:ysc, :bookings, :modification_hold_expired],
            %{count: 1},
            %{
              booking_id: booking.id,
              property: to_string(booking.property),
              booking_mode: to_string(booking.booking_mode),
              user_id: booking.user_id
            }
          )

        {:error, reason} ->
          Ysc.Logging.error("Failed to expire modification hold",
            booking_id: booking.id,
            reference_id: booking.reference_id,
            user_id: booking.user_id,
            error: reason
          )
      end
    end)

    if count > 0 do
      :telemetry.execute(
        [:ysc, :bookings, :modification_hold_expired_batch],
        %{count: count},
        %{}
      )
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: 60_000

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    now = Fixtures.now()

    from(b in Booking,
      where:
        b.status == :complete and not is_nil(b.modification_hold_expires_at) and
          b.modification_hold_expires_at < ^now
    )
  end
end
