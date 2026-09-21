defmodule Ysc.Bookings.ModificationHoldExpiryWorker do
  @moduledoc """
  Releases expired modification payment holds on completed bookings.

  When a member starts paying for a booking modification, inventory for newly
  selected dates is held briefly. This worker clears holds that were not
  completed before `modification_hold_expires_at`.

  When a PaymentIntent is stored on the hold, Stripe cancel runs *before*
  extra nights are released — the same atomic abandon path as
  `HoldExpiryWorker` / ticket TimeoutWorker. `StripeService.cancel_payment_intent/1`
  treats a succeeded Intent as `:ok`, which would orphan a captured date-change
  charge against the original stay. Booking webhooks still do not apply cabin
  modifications, so this worker is the closed-tab recovery path.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  require Ysc.Logging

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker}
  alias Ysc.Repo
  alias Ysc.Tickets.CheckoutCancel
  alias YscWeb.BookingGuestForm

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

    Enum.each(expired_bookings, &expire_one_modification_hold/1)

    if count > 0 do
      :telemetry.execute(
        [:ysc, :bookings, :modification_hold_expired_batch],
        %{count: count},
        %{}
      )
    end
  end

  defp expire_one_modification_hold(%Booking{} = booking) do
    case reconcile_modification_payment_before_release(booking) do
      :release ->
        release_expired_modification_hold(booking)

      :applied ->
        :ok

      :skip ->
        Ysc.Logging.info(
          "Skipped modification hold expiry while payment is in flight",
          booking_id: booking.id,
          reference_id: booking.reference_id,
          payment_intent_id:
            Bookings.modification_hold_payment_intent_id(booking)
        )
    end
  end

  # Cancel the PaymentIntent before releasing extra nights.
  # `StripeService.cancel_payment_intent/1` treats a succeeded Intent as `:ok`,
  # which would orphan a captured charge against dates that never changed.
  defp reconcile_modification_payment_before_release(%Booking{} = booking) do
    case Bookings.modification_hold_payment_intent_id(booking) do
      nil ->
        :release

      payment_intent_id ->
        case CheckoutCancel.cancel_payment_intent_for_abandoned_checkout(
               payment_intent_id,
               "modification_hold_expiry_worker"
             ) do
          {:cancel, _payment_intent} ->
            :release

          {:already_succeeded, payment_intent} ->
            apply_succeeded_modification_payment(booking, payment_intent)

          {:in_progress, _payment_intent} ->
            :skip

          {:error, stripe_error} ->
            Ysc.Logging.warning(
              "Could not reconcile modification hold payment with Stripe, not expiring hold",
              booking_id: booking.id,
              payment_intent_id: payment_intent_id,
              error: inspect(stripe_error)
            )

            :skip
        end
    end
  end

  defp apply_succeeded_modification_payment(
         %Booking{} = booking,
         %Stripe.PaymentIntent{} = payment_intent
       ) do
    hold_attrs = booking.modification_hold_attrs
    params = Bookings.modification_hold_form_params(booking)

    cond do
      is_nil(params) ->
        Ysc.Logging.error(
          "Modification payment succeeded during hold expiry but hold attrs could not be applied",
          booking_id: booking.id,
          payment_intent_id: payment_intent.id
        )

        Bookings.maybe_refund_unfulfilled_modification_payment(
          booking,
          payment_intent,
          :modification_hold_expired
        )

        :release

      true ->
        apply_verified_modification_payment(
          booking,
          params,
          hold_attrs,
          payment_intent
        )
    end
  end

  defp apply_verified_modification_payment(
         %Booking{} = booking,
         params,
         hold_attrs,
         %Stripe.PaymentIntent{} = payment_intent
       ) do
    case Bookings.apply_modification(booking, params,
           payment_intent_id: payment_intent.id
         ) do
      {:ok, updated_booking} ->
        sync_guests_after_expiry_apply(updated_booking, hold_attrs, booking)

        Ysc.Logging.info(
          "Applied booking modification after payment succeeded during hold expiry reconcile",
          booking_id: updated_booking.id,
          reference_id: updated_booking.reference_id,
          payment_intent_id: payment_intent.id
        )

        :telemetry.execute(
          [:ysc, :bookings, :modification_hold_expired_payment_applied],
          %{count: 1},
          %{
            booking_id: updated_booking.id,
            property: to_string(updated_booking.property),
            booking_mode: to_string(updated_booking.booking_mode),
            user_id: updated_booking.user_id
          }
        )

        :applied

      {:error, :no_changes} ->
        ensure_modification_ledger_after_expiry(booking, payment_intent)
        :applied

      {:error, {:ledger_payment_failed, reason}} ->
        Ysc.Logging.error(
          "Modification applied during hold expiry but ledger payment recording failed",
          booking_id: booking.id,
          payment_intent_id: payment_intent.id,
          error: inspect(reason)
        )

        :applied

      {:error, reason} ->
        Ysc.Logging.error(
          "Payment succeeded during modification hold expiry but the date change could not be applied",
          booking_id: booking.id,
          payment_intent_id: payment_intent.id,
          error: inspect(reason)
        )

        Bookings.maybe_refund_unfulfilled_modification_payment(
          booking,
          payment_intent,
          reason
        )

        :release
    end
  end

  defp sync_guests_after_expiry_apply(
         updated_booking,
         hold_attrs,
         original_booking
       ) do
    case BookingGuestForm.sync_guests_after_modification_apply(
           updated_booking,
           hold_attrs,
           original_booking
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        Ysc.Logging.error(
          "Modification applied during hold expiry but guest details could not be saved",
          booking_id: updated_booking.id,
          error: inspect(reason)
        )
    end
  end

  defp ensure_modification_ledger_after_expiry(booking, payment_intent) do
    case Bookings.ensure_modification_ledger_recorded(
           booking,
           payment_intent.id
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        Ysc.Logging.error(
          "Modification already applied during hold expiry but ledger payment recording failed",
          booking_id: booking.id,
          payment_intent_id: payment_intent.id,
          error: inspect(reason)
        )
    end
  end

  defp release_expired_modification_hold(%Booking{} = booking) do
    case BookingLocker.release_modification_hold(booking.id, clear_attrs: false) do
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
