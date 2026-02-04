defmodule Ysc.EventsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Events` context.
  """

  alias Ysc.Events

  def event_fixture(attrs \\ %{}) do
    organizer_id =
      attrs[:organizer_id] || Ysc.AccountsFixtures.user_fixture().id

    {:ok, event} =
      attrs
      |> Enum.into(%{
        title: "Test Event #{System.unique_integer()}",
        description: "A test event description",
        state: :published,
        organizer_id: organizer_id,
        start_date:
          DateTime.add(DateTime.utc_now(), 1, :day)
          |> DateTime.truncate(:second),
        end_date:
          DateTime.add(DateTime.utc_now(), 2, :day)
          |> DateTime.truncate(:second),
        max_attendees: 100,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Events.create_event()

    event
  end

  def ticket_tier_fixture(attrs \\ %{}) do
    event_id = attrs[:event_id] || event_fixture().id

    {:ok, tier} =
      attrs
      |> Enum.into(%{
        name: "General Admission",
        type: :paid,
        price: Money.new(50, :USD),
        quantity: 100,
        event_id: event_id
      })
      |> Events.create_ticket_tier()

    tier
  end
end
