defmodule Ysc.EventsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Events` context.
  """

  alias Ysc.Events

  def event_fixture(attrs \\ %{}) do
    organizer_id =
      attrs[:organizer_id] || Ysc.AccountsFixtures.user_fixture().id

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
    |> create_event_retrying_reference_id()
  end

  # `Events.create_event/1` does not retry on `events_reference_id_index`
  # collisions. The 4-character random suffix is shared by every event
  # inserted on a given UTC day, so a 51-event pagination loop running
  # alongside other async tests can collide. Retry with a fresh id.
  defp create_event_retrying_reference_id(attrs, attempts \\ 5) do
    case Events.create_event(attrs) do
      {:ok, event} ->
        event

      {:error, %Ecto.Changeset{} = changeset} when attempts > 1 ->
        if unique_reference_id_error?(changeset) do
          create_event_retrying_reference_id(attrs, attempts - 1)
        else
          raise "event_fixture failed: #{inspect(changeset.errors)}"
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        raise "event_fixture failed: #{inspect(changeset.errors)}"
    end
  end

  defp unique_reference_id_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:reference_id, {_, opts}} when is_list(opts) ->
        Keyword.get(opts, :constraint) == :unique

      _ ->
        false
    end)
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
