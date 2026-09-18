defmodule Ysc.Bookings.HoldExpiryWorkerTest do
  @moduledoc """
  Tests for HoldExpiryWorker module.

  These tests verify:
  - Expiration of expired booking holds
  - Error handling for hold release failures
  - Worker job execution

  Uses `async: false` because Stripe-first expiry tests pin `:stripe_client`
  via Application env, which races with DataCase setup in parallel tests.
  `Ysc.TestStripeClient.cancel_payment_intent/2` always succeeds, so a leaked
  client would expire a hold that should stay on `:hold` while processing.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings.{Booking, HoldExpiryWorker}
  alias Ysc.Repo

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    allow_far_future_booking_dates()
    user = user_fixture()

    # Ensure user is active
    user =
      user
      |> Ecto.Changeset.change(state: :active)
      |> Repo.update!()

    stub(Stripe.PaymentIntentMock, :list, fn _params ->
      {:ok,
       %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         url: "/v1/payment_intents"
       }}
    end)

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
    end)

    %{user: user}
  end

  describe "expire_expired_holds/0" do
    test "keeps booking on hold when release_hold fails due to missing inventory",
         %{
           user: user
         } do
      checkin_date = Date.add(Date.utc_today(), 205)
      checkout_date = Date.add(checkin_date, 2)

      # Buyout hold without property_inventory rows: release_hold cannot clear buyout_held.
      booking =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :buyout,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: 4,
            status: :hold,
            hold_expires_at:
              DateTime.add(
                DateTime.utc_now() |> DateTime.truncate(:second),
                -2,
                :hour
              ),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()

      HoldExpiryWorker.expire_expired_holds()

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :hold
    end

    test "expires bookings with expired holds", %{user: user} do
      # Create a booking with an expired hold by inserting directly
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      booking =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :room,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: 2,
            status: :hold,
            hold_expires_at:
              DateTime.add(
                DateTime.utc_now() |> DateTime.truncate(:second),
                -1,
                :hour
              ),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()

      # Verify booking is in hold status
      booking = Repo.get!(Booking, booking.id)
      assert booking.status == :hold
      assert booking.hold_expires_at != nil

      # Run the expiration worker
      HoldExpiryWorker.expire_expired_holds()

      # Verify booking is now canceled
      booking = Repo.get!(Booking, booking.id)
      assert booking.status == :canceled
    end

    test "does not expire bookings with future hold expiration", %{user: user} do
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      booking =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :room,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: 2,
            status: :hold,
            hold_expires_at:
              DateTime.add(
                DateTime.utc_now() |> DateTime.truncate(:second),
                1,
                :hour
              ),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()

      # Run the expiration worker
      HoldExpiryWorker.expire_expired_holds()

      # Verify booking is still in hold status
      booking = Repo.get!(Booking, booking.id)
      assert booking.status == :hold
    end

    test "does not expire bookings that are not in hold status", %{user: user} do
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      booking =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :room,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: 2,
            status: :draft,
            hold_expires_at:
              DateTime.add(
                DateTime.utc_now() |> DateTime.truncate(:second),
                -1,
                :hour
              ),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()

      # Run the expiration worker
      HoldExpiryWorker.expire_expired_holds()

      # Verify booking status is unchanged
      booking = Repo.get!(Booking, booking.id)
      assert booking.status == :draft
    end

    test "handles multiple expired holds", %{user: user} do
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      # Create multiple bookings with expired holds
      for i <- 1..3 do
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :room,
            checkin_date: Date.add(checkin_date, i),
            checkout_date: Date.add(checkout_date, i),
            guests_count: 2,
            status: :hold,
            hold_expires_at:
              DateTime.add(
                DateTime.utc_now() |> DateTime.truncate(:second),
                -i,
                :hour
              ),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()
      end

      # Verify all are in hold status
      expired_holds =
        Booking
        |> where(
          [b],
          b.status == :hold and b.hold_expires_at < ^DateTime.utc_now()
        )
        |> Repo.all()

      assert length(expired_holds) == 3

      # Run the expiration worker
      HoldExpiryWorker.expire_expired_holds()

      # Verify all are now canceled
      expired_holds =
        Booking
        |> where(
          [b],
          b.status == :hold and b.hold_expires_at < ^DateTime.utc_now()
        )
        |> Repo.all()

      assert expired_holds == []

      canceled_bookings =
        Booking
        |> where([b], b.status == :canceled)
        |> Repo.all()

      assert length(canceled_bookings) == 3
    end
  end

  describe "perform/1" do
    test "executes expiration and returns success" do
      result = HoldExpiryWorker.perform(%Oban.Job{})
      assert {:ok, "Expired expired booking holds"} == result
    end

    test "calls expire_expired_holds internally", %{user: user} do
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      # Create a booking with an expired hold
      %Booking{}
      |> Booking.changeset(
        %{
          user_id: user.id,
          property: :tahoe,
          booking_mode: :room,
          checkin_date: checkin_date,
          checkout_date: checkout_date,
          guests_count: 2,
          status: :hold,
          hold_expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              -1,
              :hour
            ),
          total_price: Money.new(100, :USD)
        },
        skip_validation: true
      )
      |> Repo.insert!()

      # Perform should expire the hold
      HoldExpiryWorker.perform(%Oban.Job{})

      # Verify booking was canceled
      canceled_bookings =
        Booking
        |> where([b], b.status == :canceled)
        |> Repo.all()

      assert length(canceled_bookings) == 1
    end
  end

  describe "timeout/1" do
    test "returns 60 seconds timeout" do
      job = %Oban.Job{args: %{}}
      assert HoldExpiryWorker.timeout(job) == 60_000
    end
  end

  describe "telemetry events" do
    test "emits telemetry event for expired hold", %{user: user} do
      checkin_date = Date.add(Date.utc_today(), 7)
      checkout_date = Date.add(checkin_date, 2)

      booking =
        %Booking{}
        |> Booking.changeset(
          %{
            user_id: user.id,
            property: :tahoe,
            booking_mode: :room,
            checkin_date: checkin_date,
            checkout_date: checkout_date,
            guests_count: 2,
            status: :hold,
            hold_expires_at:
              DateTime.add(
                DateTime.utc_now() |> DateTime.truncate(:second),
                -1,
                :hour
              ),
            total_price: Money.new(100, :USD)
          },
          skip_validation: true
        )
        |> Repo.insert!()

      # Attach telemetry handler
      test_pid = self()

      :telemetry.attach(
        "test-hold-expired",
        [:ysc, :bookings, :hold_expired],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

      :telemetry.attach(
        "test-hold-expired-batch",
        [:ysc, :bookings, :hold_expired_batch],
        fn event_name, measurements, metadata, _config ->
          send(
            test_pid,
            {:telemetry_batch_event, event_name, measurements, metadata}
          )
        end,
        nil
      )

      # Run the expiration worker
      HoldExpiryWorker.expire_expired_holds()

      # Verify telemetry event was emitted
      assert_receive {:telemetry_event, [:ysc, :bookings, :hold_expired],
                      %{count: 1}, metadata}

      assert metadata.booking_id == booking.id
      assert metadata.property == "tahoe"
      assert metadata.booking_mode == "room"
      assert metadata.user_id == user.id

      # Verify batch event was emitted
      assert_receive {:telemetry_batch_event,
                      [:ysc, :bookings, :hold_expired_batch], %{count: 1},
                      _metadata}

      # Cleanup telemetry handlers
      :telemetry.detach("test-hold-expired")
      :telemetry.detach("test-hold-expired-batch")
    end

    test "does not emit batch telemetry when no holds expired" do
      test_pid = self()

      :telemetry.attach(
        "test-no-batch",
        [:ysc, :bookings, :hold_expired_batch],
        fn event_name, measurements, metadata, _config ->
          send(
            test_pid,
            {:telemetry_batch_event, event_name, measurements, metadata}
          )
        end,
        nil
      )

      # Run with no expired holds
      HoldExpiryWorker.expire_expired_holds()

      # Should not receive batch event
      refute_receive {:telemetry_batch_event, _, _, _}, 100

      # Cleanup
      :telemetry.detach("test-no-batch")
    end
  end

  describe "Stripe-first hold expiry" do
    test "confirms the hold when Stripe cancel reveals payment already succeeded",
         %{user: user} do
      alias Ysc.Bookings.BookingLocker
      alias Ysc.Bookings.Entitlements

      {checkin, checkout} = locker_buyout_dates(501)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, entitlement} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :fixed_amount_off,
            property: :tahoe,
            amount_off: Money.new(25, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      payment_intent_id =
        "pi_hold_expiry_succeeded_#{System.unique_integer([:positive])}"

      booking =
        booking
        |> Ecto.Changeset.change(%{
          applied_booking_entitlement_id: entitlement.id,
          payment_intent_id: payment_intent_id,
          hold_expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              -1,
              :minute
            )
        })
        |> Repo.update!()

      amount_cents = Ysc.MoneyHelper.money_to_cents(booking.total_price)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :payment_intent_unexpected_state,
           message:
             "You cannot cancel this PaymentIntent because it has a status of succeeded",
           extra: %{}
         }}
      end)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => booking.id,
             "user_id" => user.id
           }
         }}
      end)

      HoldExpiryWorker.expire_expired_holds()

      confirmed = Repo.get!(Booking, booking.id)
      assert confirmed.status == :complete
      assert confirmed.applied_booking_entitlement_id == entitlement.id

      consumed = Entitlements.get_entitlement(entitlement.id)
      assert consumed.status == :consumed
      assert consumed.consumed_booking_id == booking.id

      payment = Ysc.Ledgers.get_payment_by_external_id(payment_intent_id)
      assert payment
      assert payment.status == :completed
      assert Money.equal?(payment.amount, booking.total_price)
    end

    test "skips expiry while PaymentIntent is still processing", %{user: user} do
      alias Ysc.Bookings.BookingLocker

      {checkin, checkout} = locker_buyout_dates(502)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      payment_intent_id =
        "pi_hold_expiry_processing_#{System.unique_integer([:positive])}"

      booking =
        booking
        |> Ecto.Changeset.change(%{
          payment_intent_id: payment_intent_id,
          hold_expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              -1,
              :minute
            )
        })
        |> Repo.update!()

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

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "processing",
           amount: 10_000,
           metadata: %{"booking_id" => booking.id}
         }}
      end)

      HoldExpiryWorker.expire_expired_holds()

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :hold
    end

    test "releases the hold and clears entitlement when Stripe accepts the cancel",
         %{user: user} do
      alias Ysc.Bookings.BookingLocker
      alias Ysc.Bookings.Entitlements

      {checkin, checkout} = locker_buyout_dates(503)

      assert {:ok, booking} =
               BookingLocker.create_buyout_booking(
                 user.id,
                 :tahoe,
                 checkin,
                 checkout,
                 4
               )

      {:ok, entitlement} =
        Entitlements.create_entitlement(
          %{
            user_id: user.id,
            issued_by_user_id: user.id,
            benefit_kind: :fixed_amount_off,
            property: :tahoe,
            amount_off: Money.new(25, :USD),
            max_guests: 10
          },
          send_notification: false
        )

      payment_intent_id =
        "pi_hold_expiry_canceled_#{System.unique_integer([:positive])}"

      booking =
        booking
        |> Ecto.Changeset.change(%{
          applied_booking_entitlement_id: entitlement.id,
          payment_intent_id: payment_intent_id,
          hold_expires_at:
            DateTime.add(
              DateTime.utc_now() |> DateTime.truncate(:second),
              -1,
              :minute
            )
        })
        |> Repo.update!()

      stub(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "canceled"
         }}
      end)

      HoldExpiryWorker.expire_expired_holds()

      released = Repo.get!(Booking, booking.id)
      assert released.status == :canceled
      assert is_nil(released.applied_booking_entitlement_id)

      still_active = Entitlements.get_entitlement(entitlement.id)
      assert still_active.status == :active
    end

    test "refunds and releases when succeeded payment amount does not match the hold",
         %{user: user} do
      alias Ysc.Bookings.Entitlements

      {booking, payment_intent_id, entitlement} =
        expired_hold_with_entitlement(user, 504)

      amount_cents = Ysc.MoneyHelper.money_to_cents(booking.total_price)

      expect_cancel_refused(payment_intent_id)

      # CheckoutCancel retrieve + create_stripe_refund retrieve. If the worker
      # skips the refund, Mox fails because the second retrieve never happens.
      expect(Ysc.StripeMock, :retrieve_payment_intent, 2, fn ^payment_intent_id,
                                                             _opts ->
        {:ok,
         succeeded_payment_intent(
           payment_intent_id,
           booking,
           user,
           amount_cents + 500
         )}
      end)

      HoldExpiryWorker.expire_expired_holds()

      released = Repo.get!(Booking, booking.id)
      assert released.status == :canceled
      assert is_nil(released.applied_booking_entitlement_id)

      still_active = Entitlements.get_entitlement(entitlement.id)
      assert still_active.status == :active

      refute Ysc.Ledgers.get_payment_by_external_id(payment_intent_id)
    end

    test "skips expiry when succeeded payment metadata does not match the hold",
         %{user: user} do
      alias Ysc.Bookings.Entitlements

      {booking, payment_intent_id, entitlement} =
        expired_hold_with_entitlement(user, 505)

      amount_cents = Ysc.MoneyHelper.money_to_cents(booking.total_price)

      expect_cancel_refused(payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok,
         succeeded_payment_intent(
           payment_intent_id,
           booking,
           user,
           amount_cents,
           metadata: %{
             "booking_id" => "not-this-booking",
             "user_id" => user.id
           }
         )}
      end)

      HoldExpiryWorker.expire_expired_holds()

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :hold
      assert reloaded.applied_booking_entitlement_id == entitlement.id

      still_active = Entitlements.get_entitlement(entitlement.id)
      assert still_active.status == :active
      refute Ysc.Ledgers.get_payment_by_external_id(payment_intent_id)
    end

    test "skips expiry when payment succeeded but booking confirmation fails",
         %{user: user} do
      alias Ysc.Bookings.Entitlements

      {booking, payment_intent_id, entitlement} =
        expired_hold_with_entitlement(user, 506)

      # Consume will fail (entitlement no longer active) while inventory is
      # still held, so a mistaken :release would cancel the hold. Skip must
      # leave seats and the applied entitlement attached for checkout/receipt.
      assert {:ok, _} = Entitlements.revoke_entitlement(entitlement)

      amount_cents = Ysc.MoneyHelper.money_to_cents(booking.total_price)

      expect_cancel_refused(payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok,
         succeeded_payment_intent(
           payment_intent_id,
           booking,
           user,
           amount_cents
         )}
      end)

      HoldExpiryWorker.expire_expired_holds()

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :hold
      assert reloaded.applied_booking_entitlement_id == entitlement.id
      refute Ysc.Ledgers.get_payment_by_external_id(payment_intent_id)
    end

    test "skips expiry when Stripe cancel fails without a PaymentIntent status",
         %{user: user} do
      {booking, payment_intent_id, _entitlement} =
        expired_hold_with_entitlement(user, 507)

      expect(Ysc.StripeMock, :cancel_payment_intent, fn ^payment_intent_id,
                                                        _opts ->
        {:error, :timeout}
      end)

      HoldExpiryWorker.expire_expired_holds()

      reloaded = Repo.get!(Booking, booking.id)
      assert reloaded.status == :hold
      assert reloaded.payment_intent_id == payment_intent_id
    end

    test "releases the hold when Stripe refused cancel because the PI is already canceled",
         %{user: user} do
      alias Ysc.Bookings.Entitlements

      {booking, payment_intent_id, entitlement} =
        expired_hold_with_entitlement(user, 508)

      expect_cancel_refused(payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "canceled"
         }}
      end)

      HoldExpiryWorker.expire_expired_holds()

      released = Repo.get!(Booking, booking.id)
      assert released.status == :canceled
      assert is_nil(released.applied_booking_entitlement_id)

      still_active = Entitlements.get_entitlement(entitlement.id)
      assert still_active.status == :active
    end
  end

  defp expired_hold_with_entitlement(user, slot) do
    alias Ysc.Bookings.BookingLocker
    alias Ysc.Bookings.Entitlements

    {checkin, checkout} = locker_buyout_dates(slot)

    assert {:ok, booking} =
             BookingLocker.create_buyout_booking(
               user.id,
               :tahoe,
               checkin,
               checkout,
               4
             )

    {:ok, entitlement} =
      Entitlements.create_entitlement(
        %{
          user_id: user.id,
          issued_by_user_id: user.id,
          benefit_kind: :fixed_amount_off,
          property: :tahoe,
          amount_off: Money.new(25, :USD),
          max_guests: 10
        },
        send_notification: false
      )

    payment_intent_id =
      "pi_hold_expiry_edge_#{slot}_#{System.unique_integer([:positive])}"

    booking =
      booking
      |> Ecto.Changeset.change(%{
        applied_booking_entitlement_id: entitlement.id,
        payment_intent_id: payment_intent_id,
        hold_expires_at:
          DateTime.add(
            DateTime.utc_now() |> DateTime.truncate(:second),
            -1,
            :minute
          )
      })
      |> Repo.update!()

    {booking, payment_intent_id, entitlement}
  end

  defp expect_cancel_refused(payment_intent_id) do
    # Stub rather than expect: amount-mismatch / already-canceled paths
    # release the hold afterwards, and release_hold cancels the PI again.
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

  defp succeeded_payment_intent(
         payment_intent_id,
         booking,
         user,
         amount_cents,
         opts \\ []
       ) do
    %Stripe.PaymentIntent{
      id: payment_intent_id,
      status: "succeeded",
      amount: amount_cents,
      latest_charge: "ch_#{payment_intent_id}",
      metadata:
        Keyword.get(opts, :metadata, %{
          "booking_id" => booking.id,
          "user_id" => user.id
        })
    }
  end
end
