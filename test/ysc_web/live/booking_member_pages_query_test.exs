defmodule YscWeb.BookingMemberPagesQueryTest do
  @moduledoc """
  Query-count assertions for member booking checkout, detail, and receipt loads.
  """
  use YscWeb.ConnCase, async: false, mox_global_first: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Ysc.TestDataFactory
  import Mox

  alias Ysc.Bookings
  alias Ysc.Bookings.{BookingGuest, Room, RoomCategory}
  alias Ysc.Ledgers
  alias Ysc.Repo
  alias Ysc.StripeMock

  setup %{conn: conn} do
    Ledgers.ensure_basic_accounts()
    ensure_buyout_base_pricing!()
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, StripeMock)

    stub(StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_query_test_123",
         client_secret: "pi_query_test_123_secret",
         status: "requires_payment_method",
         amount: params.amount
       }}
    end)

    stub(StripeMock, :retrieve_payment_intent, fn _id, _opts ->
      {:error, :not_stubbed}
    end)

    stub(StripeMock, :cancel_payment_intent, fn id, _opts ->
      {:ok, %Stripe.PaymentIntent{id: id, status: "canceled"}}
    end)

    {:ok, conn: conn}
  end

  describe "booking checkout payment step" do
    test "connected payment checkout does not query room categories or family users",
         %{conn: conn} do
      user = user_with_membership()

      booking =
        booking_fixture(%{
          user_id: user.id,
          status: :hold,
          property: :clear_lake,
          booking_mode: :buyout
        })

      conn = log_in_user(conn, user)
      category_pattern = ~r/FROM ["']?room_categories["']?/i
      family_pattern = ~r/"primary_user_id" =/i

      {{:ok, view, html}, category_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} =
              live(conn, ~p"/bookings/checkout/#{booking.id}")

            render(view)
            {:ok, view, html}
          end,
          pattern: category_pattern
        )

      {{:ok, _view, _html}, family_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} =
              live(conn, ~p"/bookings/checkout/#{booking.id}")

            render(view)
            {:ok, view, html}
          end,
          pattern: family_pattern
        )

      assert category_queries == 0
      assert family_queries == 0
      assert html =~ "Complete Your Booking"

      assert has_element?(view, "#stripe-payment-container") or
               html =~ "Confirm your booking"
    end
  end

  describe "booking detail" do
    test "connected detail render skips room categories",
         %{conn: conn} do
      user = user_fixture()
      {booking, room} = room_booking_for_user(user, :complete)
      conn = log_in_user(conn, user)

      {{:ok, view, html}, category_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} = live(conn, ~p"/bookings/#{booking.id}")
            render(view)
            {:ok, view, html}
          end,
          pattern: ~r/FROM ["']?room_categories["']?/i
        )

      assert category_queries == 0
      assert html =~ room.name

      assert has_element?(view, "#booking-detail-loading") == false or
               html =~ "Booking Details"
    end
  end

  describe "booking receipt" do
    test "connected receipt render skips room categories",
         %{conn: conn} do
      user = user_fixture()
      {booking, room} = room_booking_for_user(user, :complete)
      conn = log_in_user(conn, user)

      {{:ok, _view, html}, category_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            {:ok, view, html} =
              live(conn, ~p"/bookings/#{booking.id}/receipt")

            render(view)
            {:ok, view, html}
          end,
          pattern: ~r/FROM ["']?room_categories["']?/i
        )

      assert category_queries == 0
      assert html =~ room.name
    end
  end

  defp room_booking_for_user(user, status) do
    {:ok, category} =
      %RoomCategory{}
      |> RoomCategory.changeset(%{
        name: "qc-#{System.unique_integer([:positive])}",
        notes: "member pages must not load category notes"
      })
      |> Repo.insert()

    {:ok, room} =
      %Room{}
      |> Room.changeset(%{
        name: "Query Count Room",
        description: "member pages must not load room description",
        property: :tahoe,
        capacity_max: 2,
        is_active: true,
        room_category_id: category.id
      })
      |> Repo.insert()

    booking =
      booking_fixture(%{
        user_id: user.id,
        status: status,
        property: :tahoe,
        booking_mode: :room,
        rooms: [room]
      })

    {:ok, _} =
      %BookingGuest{}
      |> BookingGuest.changeset(%{
        booking_id: booking.id,
        first_name: user.first_name || "Pat",
        last_name: user.last_name || "Member",
        is_child: false,
        is_booking_user: true,
        order_index: 0
      })
      |> Repo.insert()

    {Repo.reload!(booking), room}
  end

  defp ensure_buyout_base_pricing! do
    for prop <- [:tahoe, :clear_lake] do
      case Bookings.create_pricing_rule(%{
             amount: Money.new(430, :USD),
             booking_mode: :buyout,
             price_unit: :buyout_fixed,
             property: prop,
             season_id: nil,
             room_id: nil,
             room_category_id: nil
           }) do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{} = cs} ->
          if Enum.any?(cs.errors, fn {_field, {_msg, meta}} ->
               meta[:constraint] == :unique
             end) do
            :ok
          else
            flunk(
              "unexpected Bookings.create_pricing_rule failure: #{inspect(cs.errors)}"
            )
          end

        {:error, other} ->
          flunk(
            "unexpected Bookings.create_pricing_rule result: #{inspect(other)}"
          )
      end
    end

    :ok
  end
end
