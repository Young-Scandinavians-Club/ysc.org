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

    test "exposes type metadata and equality through the parameterized type" do
      params = DateKind.init(kind: :utc_instant)
      type = {:parameterized, {DateKind, params}}

      assert DateKind.type(params) == :utc_datetime
      assert DateKind.embed_as(:json, params) == :self
      assert DateKind.valid_kind?(:utc_instant)
      refute DateKind.valid_kind?(:not_a_kind)
      assert :utc_instant in DateKind.kinds()
      assert is_binary(DateKind.display_hint(:utc_instant))

      assert {:ok, ~U[2026-08-28 00:00:00Z]} =
               DateKind.load(
                 ~U[2026-08-28 00:00:00Z],
                 fn v -> {:ok, v} end,
                 params
               )

      assert {:ok, ~U[2026-08-28 00:00:00Z]} =
               DateKind.dump(
                 ~U[2026-08-28 00:00:00Z],
                 fn v -> {:ok, v} end,
                 params
               )

      assert DateKind.equal?(
               ~U[2026-08-28 00:00:00Z],
               ~U[2026-08-28 00:00:00Z],
               params
             )

      refute DateKind.equal?(
               ~U[2026-08-28 00:00:00Z],
               ~U[2026-08-29 00:00:00Z],
               params
             )

      assert Ecto.Type.equal?(
               type,
               ~U[2026-08-28 00:00:00Z],
               ~U[2026-08-28 00:00:00Z]
             )
    end
  end

  describe "DateFields.kind/2" do
    test "returns nil for unknown schemas, fields, and non-atom arguments" do
      assert DateFields.kind(String, :start_date) == nil
      assert DateFields.kind(Event, :not_a_date_field) == nil
      assert DateFields.kind("Event", :start_date) == nil
      assert DateFields.kind(Event, "start_date") == nil
    end

    test "unwraps both parameterized type tuple shapes" do
      params = %{kind: :utc_instant}

      assert DateFields.unwrap_kind({:parameterized, {DateKind, params}}) ==
               :utc_instant

      assert DateFields.unwrap_kind({:parameterized, DateKind, params}) ==
               :utc_instant

      assert DateFields.unwrap_kind(:utc_datetime) == nil
    end

    test "maps receiver names to schemas" do
      assert DateFields.schema_for_receiver(:event) == Event
      assert DateFields.schema_for_receiver(:unknown) == nil
      assert :start_date in DateFields.required_field_names()
    end
  end
end
