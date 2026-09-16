defmodule Ysc.Bookings.HoldExpiryWorker do
  @moduledoc """
  Background worker for handling booking hold expiry.

  This worker runs periodically to:
  - Find bookings with status = :hold AND hold_expires_at < now()
  - Stripe-reconcile any attached PaymentIntent *before* releasing inventory
    (same atomic abandon path as ticket TimeoutWorker)
  - When Stripe already captured, confirm the hold while seats and entitlements
    are still attached
  - Otherwise lock inventory rows, reverse the hold, move to :canceled, and
    release inventory back to available
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  require Ysc.Logging

  alias Ysc.Bookings.{Booking, BookingLocker}
  alias Ysc.Tickets.CheckoutCancel

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    expire_expired_holds()
    {:ok, "Expired expired booking holds"}
  end

  @doc """
  Manually trigger expiration of expired holds.
  This can be called from a cron job or scheduled task.
  """
  def expire_expired_holds do
    now = DateTime.utc_now()

    expired_bookings =
      Booking
      |> where([b], b.status == :hold and b.hold_expires_at < ^now)
      |> Ysc.Repo.all()

    count = length(expired_bookings)

    Enum.each(expired_bookings, &expire_one_hold/1)

    # Emit aggregate telemetry event
    if count > 0 do
      :telemetry.execute(
        [:ysc, :bookings, :hold_expired_batch],
        %{count: count},
        %{}
      )
    end
  end

  defp expire_one_hold(%Booking{} = booking) do
    case reconcile_hold_payment_before_release(booking) do
      :release ->
        release_expired_hold(booking)

      :confirmed ->
        :ok

      :skip ->
        Ysc.Logging.info(
          "Skipped booking hold expiry while checkout payment is in flight",
          booking_id: booking.id,
          reference_id: booking.reference_id,
          payment_intent_id: booking.payment_intent_id
        )
    end
  end

  # Cancel the PaymentIntent before releasing seats. `StripeService.cancel_payment_intent/1`
  # treats a succeeded Intent as `:ok`, which would orphan a captured charge against
  # a canceled hold and clear `applied_booking_entitlement_id` so late confirm never
  # consumes the benefit. Stripe cancel is the atomic arbiter (ticket TimeoutWorker).
  defp reconcile_hold_payment_before_release(
         %Booking{payment_intent_id: payment_intent_id} = booking
       )
       when is_binary(payment_intent_id) and payment_intent_id != "" do
    case CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
           payment_intent_id,
           "hold_expiry_worker"
         ) do
      {:cancel, _payment_intent} ->
        :release

      {:already_succeeded, payment_intent} ->
        confirm_succeeded_hold_payment(booking, payment_intent)

      {:in_progress, _payment_intent} ->
        :skip

      {:error, stripe_error} ->
        Ysc.Logging.warning(
          "Could not reconcile booking hold payment with Stripe, not expiring hold",
          booking_id: booking.id,
          payment_intent_id: payment_intent_id,
          error: inspect(stripe_error)
        )

        :skip
    end
  end

  defp reconcile_hold_payment_before_release(_booking), do: :release

  defp confirm_succeeded_hold_payment(
         %Booking{} = booking,
         %Stripe.PaymentIntent{} = payment_intent
       ) do
    case Ysc.Bookings.verify_booking_payment_intent(payment_intent, booking) do
      :ok ->
        confirm_verified_hold_payment(booking, payment_intent)

      {:error, :payment_amount_mismatch} = error ->
        Ysc.Logging.error(
          "Payment succeeded during hold expiry but amount did not match the hold",
          booking_id: booking.id,
          payment_intent_id: payment_intent.id,
          error: inspect(error)
        )

        Ysc.Bookings.maybe_refund_unfulfilled_checkout_payment(
          booking,
          payment_intent,
          :payment_amount_mismatch
        )

        # Charge does not match this hold — release so the entitlement is not
        # stuck and inventory is not held against an unfulfillable payment.
        :release

      {:error, reason} ->
        Ysc.Logging.error(
          "Payment succeeded during hold expiry but could not be verified for this hold",
          booking_id: booking.id,
          payment_intent_id: payment_intent.id,
          error: inspect(reason)
        )

        :skip
    end
  end

  defp confirm_verified_hold_payment(
         %Booking{} = booking,
         %Stripe.PaymentIntent{} = payment_intent
       ) do
    case BookingLocker.confirm_booking(booking.id) do
      {:ok, confirmed} ->
        case Ysc.Bookings.record_hold_checkout_ledger_payment(
               confirmed,
               payment_intent
             ) do
          :ok ->
            :ok

          {:error, ledger_reason} ->
            Ysc.Logging.error(
              "Booking confirmed during hold expiry but ledger payment recording failed",
              booking_id: confirmed.id,
              payment_intent_id: payment_intent.id,
              error: inspect(ledger_reason)
            )
        end

        Ysc.Logging.info(
          "Confirmed booking hold after payment succeeded during hold expiry reconcile",
          booking_id: confirmed.id,
          reference_id: confirmed.reference_id,
          payment_intent_id: payment_intent.id
        )

        :telemetry.execute(
          [:ysc, :bookings, :hold_expired_payment_confirmed],
          %{count: 1},
          %{
            booking_id: confirmed.id,
            property: to_string(confirmed.property),
            booking_mode: to_string(confirmed.booking_mode),
            user_id: confirmed.user_id
          }
        )

        :confirmed

      {:error, reason} ->
        Ysc.Logging.error(
          "Payment succeeded during hold expiry but booking could not be confirmed",
          booking_id: booking.id,
          payment_intent_id: payment_intent.id,
          error: inspect(reason)
        )

        # Leave the hold in place so LiveView/receipt can reclaim or refund
        # with the entitlement still attached. Do not release inventory.
        :skip
    end
  end

  defp release_expired_hold(%Booking{} = booking) do
    case BookingLocker.release_hold(booking.id) do
      {:ok, _updated_booking} ->
        Ysc.Logging.info("Expired booking hold due to timeout",
          booking_id: booking.id,
          reference_id: booking.reference_id,
          user_id: booking.user_id,
          property: booking.property,
          booking_mode: booking.booking_mode
        )

        :telemetry.execute(
          [:ysc, :bookings, :hold_expired],
          %{count: 1},
          %{
            booking_id: booking.id,
            property: to_string(booking.property),
            booking_mode: to_string(booking.booking_mode),
            user_id: booking.user_id
          }
        )

      {:error, reason} ->
        Ysc.Logging.error("Failed to expire booking hold",
          booking_id: booking.id,
          reference_id: booking.reference_id,
          user_id: booking.user_id,
          error: reason
        )
    end
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Job timeout after 60 seconds (may need to process multiple bookings)
    60_000
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    now = Fixtures.now()

    from(b in Booking, where: b.status == :hold and b.hold_expires_at < ^now)
  end
end
