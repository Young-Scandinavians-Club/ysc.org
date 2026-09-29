defmodule Ysc.Bookings.ModificationHoldExpiryWorkerTest do
  @moduledoc """
  Tests for ModificationHoldExpiryWorker.

  Uses `async: false` because Stripe-first expiry tests pin `:stripe_client`
  via Application env, which races with DataCase setup in parallel tests.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Mox

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker, ModificationHoldExpiryWorker}
  alias Ysc.Repo

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    Ysc.TestHelpers.setup_quickbooks_mocks()

    user =
      user_fixture()
      |> Ecto.Changeset.change(state: :active)
      |> Repo.update!()

    {:ok, _} =
      Ysc.Bookings.create_pricing_rule(%{
        amount: Money.new(500, :USD),
        booking_mode: :buyout,
        price_unit: :buyout_fixed,
        property: :tahoe,
        season_id: nil
      })

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
    end)

    %{user: user}
  end

  test "expires stale modification holds", %{user: user} do
    {booking, _extended_checkout} = expired_modification_hold!(user)

    ModificationHoldExpiryWorker.expire_expired_modification_holds()

    reloaded = Repo.get!(Booking, booking.id)
    assert is_nil(reloaded.modification_hold_expires_at)
    assert reloaded.modification_hold_attrs

    assert reloaded.modification_hold_attrs["checkout_date"] ==
             Date.to_iso8601(booking.checkout_date |> Date.add(1))
  end

  test "applies the date change when expiry races a succeeded PaymentIntent",
       %{user: user} do
    {booking, extended_checkout, preview} =
      expired_modification_hold_with_preview!(user)

    payment_intent_id =
      "pi_mod_hold_expiry_succeeded_#{System.unique_integer([:positive])}"

    amount_cents = Ysc.MoneyHelper.money_to_cents(preview.delta)

    assert {:ok, _} =
             Bookings.attach_modification_payment_intent(
               booking.id,
               payment_intent_id
             )

    booking = expire_modification_hold!(Repo.get!(Booking, booking.id))

    expect_cancel_refused(payment_intent_id)

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      {:ok,
       succeeded_modification_payment_intent(
         payment_intent_id,
         booking,
         user,
         amount_cents
       )}
    end)

    ModificationHoldExpiryWorker.expire_expired_modification_holds()

    updated = Repo.get!(Booking, booking.id)
    assert updated.checkout_date == extended_checkout
    assert is_nil(updated.modification_hold_expires_at)
    assert is_nil(updated.modification_hold_attrs)
    assert Bookings.modification_ledger_recorded?(booking.id, payment_intent_id)
  end

  test "skips expiry while the modification PaymentIntent is still processing",
       %{user: user} do
    {booking, _extended_checkout} = expired_modification_hold!(user)

    payment_intent_id =
      "pi_mod_hold_expiry_processing_#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             Bookings.attach_modification_payment_intent(
               booking.id,
               payment_intent_id
             )

    booking = expire_modification_hold!(Repo.get!(Booking, booking.id))
    original_checkout = booking.checkout_date

    expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :payment_intent_unexpected_state,
         message:
           "You cannot cancel this PaymentIntent because it has a status of processing",
         extra: %{}
       }}
    end)

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
      {:ok, %Stripe.PaymentIntent{id: payment_intent_id, status: "processing"}}
    end)

    ModificationHoldExpiryWorker.expire_expired_modification_holds()

    reloaded = Repo.get!(Booking, booking.id)
    assert reloaded.checkout_date == original_checkout
    assert reloaded.modification_hold_expires_at

    assert reloaded.modification_hold_attrs["payment_intent_id"] ==
             payment_intent_id
  end

  test "releases the hold when Stripe accepts the modification PaymentIntent cancel",
       %{user: user} do
    {booking, extended_checkout} = expired_modification_hold!(user)

    payment_intent_id =
      "pi_mod_hold_expiry_canceled_#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             Bookings.attach_modification_payment_intent(
               booking.id,
               payment_intent_id
             )

    booking = expire_modification_hold!(Repo.get!(Booking, booking.id))
    original_checkout = booking.checkout_date

    stub(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id, _opts ->
      {:ok, %Stripe.PaymentIntent{id: payment_intent_id, status: "canceled"}}
    end)

    ModificationHoldExpiryWorker.expire_expired_modification_holds()

    released = Repo.get!(Booking, booking.id)
    assert released.checkout_date == original_checkout
    assert is_nil(released.modification_hold_expires_at)
    assert released.modification_hold_attrs

    assert released.modification_hold_attrs["checkout_date"] ==
             Date.to_iso8601(extended_checkout)

    refute Bookings.modification_ledger_recorded?(booking.id, payment_intent_id)
  end

  defp expired_modification_hold!(user) do
    {booking, extended_checkout, _preview} =
      expired_modification_hold_with_preview!(user)

    {expire_modification_hold!(booking), extended_checkout}
  end

  defp expired_modification_hold_with_preview!(user) do
    {checkin, checkout} = tahoe_booking_dates(130)
    extended_checkout = Date.add(checkout, 1)

    assert {:ok, total, _} =
             Ysc.Bookings.calculate_booking_price(
               :tahoe,
               checkin,
               checkout,
               :buyout,
               guests_count: 4
             )

    assert {:ok, %Booking{} = booking} =
             BookingLocker.create_admin_booking(
               %{
                 user_id: user.id,
                 property: :tahoe,
                 checkin_date: checkin,
                 checkout_date: checkout,
                 booking_mode: :buyout,
                 guests_count: 4,
                 total_price: total
               },
               skip_email: true,
               skip_reminders: true
             )

    attrs = %{
      checkin_date: checkin,
      checkout_date: extended_checkout,
      guests_count: 4,
      children_count: 0
    }

    assert {:ok, preview} =
             Bookings.prepare_modification(booking, %{
               "checkin_date" => Date.to_string(checkin),
               "checkout_date" => Date.to_string(extended_checkout),
               "guests_count" => "4",
               "children_count" => "0"
             })

    assert Money.positive?(preview.delta)

    assert {:ok, held_booking} =
             Ysc.Bookings.place_modification_hold(booking, attrs)

    {held_booking, extended_checkout, preview}
  end

  defp expire_modification_hold!(booking) do
    booking
    |> Ecto.Changeset.change(
      modification_hold_expires_at:
        DateTime.add(
          DateTime.utc_now() |> DateTime.truncate(:second),
          -5,
          :minute
        )
    )
    |> Repo.update!()
  end

  defp expect_cancel_refused(payment_intent_id) do
    stub(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id, _opts ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :payment_intent_unexpected_state,
         message:
           "You cannot cancel this PaymentIntent because it has a status of succeeded",
         extra: %{}
       }}
    end)
  end

  defp succeeded_modification_payment_intent(
         payment_intent_id,
         booking,
         user,
         amount_cents
       ) do
    %Stripe.PaymentIntent{
      id: payment_intent_id,
      status: "succeeded",
      amount: amount_cents,
      latest_charge: %Stripe.Charge{id: "ch_#{payment_intent_id}"},
      metadata: %{
        "booking_id" => to_string(booking.id),
        "user_id" => to_string(user.id),
        "modification" => "true"
      }
    }
  end
end
