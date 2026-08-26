defmodule Ysc.Ecto.DateKindTest do
  use ExUnit.Case, async: true

  alias Ysc.DateFields
  alias Ysc.Ecto.DateKind
  alias Ysc.Ecto.DateKindSample
  alias Ysc.Events.Event

  describe "schema configuration" do
    test "loads Event.start_date as a california calendar DateTime" do
      assert DateFields.kind(Event, :start_date) ==
               :california_calendar_datetime

      assert DateFields.kind(Ysc.Events.TicketTier, :start_date) ==
               :pacific_anchored_datetime

      assert DateFields.kind(Ysc.Bookings.Booking, :checkin_date) ==
               :california_date

      assert DateFields.kind(Ysc.Posts.Post, :published_on) == :utc_instant

      assert DateFields.kind(Ysc.Subscriptions.Subscription, :start_date) ==
               :utc_instant
    end

    test "casts using the underlying primitive" do
      type = DateKindSample.__schema__(:type, :start_date)

      assert {:ok, ~U[2026-08-28 00:00:00Z]} =
               Ecto.Type.cast(type, ~U[2026-08-28 00:00:00Z])

      assert {:ok, ~D[2026-08-28]} =
               Ecto.Type.cast(
                 DateKindSample.__schema__(:type, :checkin_date),
                 ~D[2026-08-28]
               )
    end
  end

  describe "DateKind metadata" do
    test "shift_zone is forbidden for california calendar kinds" do
      assert DateKind.shift_zone_policy(:california_calendar_datetime) == :never
      assert DateKind.shift_zone_policy(:california_date) == :never
      assert DateKind.shift_zone_policy(:pacific_time) == :never
      assert DateKind.shift_zone_policy(:pacific_anchored_datetime) == :pacific
      assert DateKind.shift_zone_policy(:utc_instant) == :browser
    end

    test "rejects unknown kinds at init" do
      assert_raise ArgumentError, fn -> DateKind.init(kind: :not_a_kind) end
      assert_raise ArgumentError, fn -> DateKind.init([]) end
    end
  end
end
