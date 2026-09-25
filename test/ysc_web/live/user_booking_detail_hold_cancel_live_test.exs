defmodule YscWeb.UserBookingDetailHoldCancelLiveTest do
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Bookings.BookingLocker
  alias Ysc.Ledgers
  alias Ysc.Repo
  alias Ysc.StripeMock

  setup %{conn: conn} do
    Ledgers.ensure_basic_accounts()
    allow_far_future_booking_dates()

    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, StripeMock)

    stub(Stripe.PaymentIntentMock, :list, fn _params ->
      {:ok,
       %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         url: "/v1/payment_intents"
       }}
    end)

    {:ok, conn: conn}
  end

  describe "confirm-cancel hold Stripe-first reconcile" do
    setup :verify_on_exit!

    test "navigates to receipt when hold PaymentIntent already succeeded", %{
      conn: conn
    } do
      user =
        user_fixture()
        |> Ecto.Changeset.change(%{state: :active})
        |> Repo.update!()

      {hold, payment_intent_id} = hold_with_payment_intent(user, 430)
      amount_cents = Ysc.MoneyHelper.money_to_cents(hold.total_price)

      expect(StripeMock, :cancel_payment_intent, fn ^payment_intent_id, _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :payment_intent_unexpected_state,
           message:
             "You cannot cancel this PaymentIntent because it has a status of succeeded",
           extra: %{}
         }}
      end)

      expect(StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "succeeded",
           amount: amount_cents,
           metadata: %{
             "booking_id" => hold.id,
             "user_id" => user.id
           }
         }}
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/bookings/#{hold.id}")
      _html = render(view)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()
      assert has_element?(view, "#cancel-booking-form")

      assert {:error, {:live_redirect, %{to: receipt_path}}} =
               view
               |> form("#cancel-booking-form", %{"reason" => "Changed plans"})
               |> render_submit()

      assert receipt_path == ~p"/bookings/#{hold.id}/receipt"

      confirmed = Repo.reload!(hold)
      assert confirmed.status == :complete

      payment = Ledgers.get_payment_by_external_id(payment_intent_id)
      assert payment
      assert payment.status == :completed
    end

    test "keeps the hold and toasts when PaymentIntent is still processing", %{
      conn: conn
    } do
      user =
        user_fixture()
        |> Ecto.Changeset.change(%{state: :active})
        |> Repo.update!()

      {hold, payment_intent_id} = hold_with_payment_intent(user, 431)

      expect(StripeMock, :cancel_payment_intent, fn ^payment_intent_id, _opts ->
        {:error,
         %Stripe.Error{
           source: :stripe,
           code: :payment_intent_unexpected_state,
           message:
             "You cannot cancel this PaymentIntent because it has a status of processing",
           extra: %{}
         }}
      end)

      expect(StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                      _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "processing",
           amount: 10_000,
           metadata: %{"booking_id" => hold.id}
         }}
      end)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/bookings/#{hold.id}")
      _html = render(view)

      view |> element("button[phx-click='show-cancel-modal']") |> render_click()

      html =
        view
        |> form("#cancel-booking-form", %{"reason" => "Changed plans"})
        |> render_submit()

      assert html =~ "still processing"
      refute has_element?(view, "#cancel-booking-modal")

      reloaded = Repo.reload!(hold)
      assert reloaded.status == :hold
      assert reloaded.payment_intent_id == payment_intent_id
    end
  end

  defp hold_with_payment_intent(user, slot) do
    {checkin, checkout} = locker_buyout_dates(slot)

    assert {:ok, hold} =
             BookingLocker.create_buyout_booking(
               user.id,
               :tahoe,
               checkin,
               checkout,
               4
             )

    payment_intent_id =
      "pi_hold_cancel_lv_#{slot}_#{System.unique_integer([:positive])}"

    hold =
      hold
      |> Ecto.Changeset.change(%{payment_intent_id: payment_intent_id})
      |> Repo.update!()

    {hold, payment_intent_id}
  end
end
