defmodule Ysc.DateFields do
  @moduledoc """
  Looks up timezone conversion kind from a schema field's `Ysc.Ecto.DateKind`.

  The kind lives on the field (`field :start_date, Ysc.Ecto.DateKind, kind: :…`).
  This module is the runtime/linter API over that configuration.

  Ambiguous field names listed in `required_field_names/0` **must** use
  `Ysc.Ecto.DateKind` (Credo `EX9003`).
  """

  alias Ysc.Ecto.DateKind

  @required_field_names [
    :start_date,
    :end_date,
    :checkin_date,
    :checkout_date,
    :start_time,
    :end_time,
    :published_on,
    :day
  ]

  @receiver_schemas %{
    event: Ysc.Events.Event,
    hero_event: Ysc.Events.Event,
    upcoming_event: Ysc.Events.Event,
    current_event: Ysc.Events.Event,
    ticket_tier: Ysc.Events.TicketTier,
    agenda_item: Ysc.Events.AgendaItem,
    booking: Ysc.Bookings.Booking,
    season: Ysc.Bookings.Season,
    blackout: Ysc.Bookings.Blackout,
    post: Ysc.Posts.Post,
    subscription: Ysc.Subscriptions.Subscription,
    room_inventory: Ysc.Bookings.RoomInventory,
    property_inventory: Ysc.Bookings.PropertyInventory
  }

  @doc """
  Field names that cannot stay as a bare `:utc_datetime`, `:date`, or `:time`.
  """
  def required_field_names, do: @required_field_names

  @doc "Maps a conventional variable/assign name to a schema module."
  def schema_for_receiver(name) when is_atom(name),
    do: Map.get(@receiver_schemas, name)

  @doc """
  Returns the `Ysc.Ecto.DateKind` kind for `schema.field`, or `nil` when the
  field is not a DateKind type.
  """
  def kind(schema, field) when is_atom(schema) and is_atom(field) do
    with {:module, _} <- Code.ensure_loaded(schema),
         true <- function_exported?(schema, :__schema__, 2) do
      unwrap_kind(schema.__schema__(:type, field))
    else
      _ -> nil
    end
  end

  def kind(_, _), do: nil

  @doc false
  def unwrap_kind({:parameterized, {DateKind, %{kind: kind}}})
      when is_atom(kind),
      do: kind

  def unwrap_kind({:parameterized, DateKind, %{kind: kind}})
      when is_atom(kind),
      do: kind

  def unwrap_kind(_), do: nil
end
