defmodule Ysc.Events.PickerTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias Ysc.Events.Picker

  defp days_from_now(days) do
    DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.truncate(:second)
  end

  defp event_in(days, attrs \\ %{}) do
    event_fixture(
      Map.merge(
        %{
          title: "Event #{System.unique_integer([:positive])}",
          start_date: days_from_now(days),
          end_date: days_from_now(days + 1)
        },
        Map.new(attrs)
      )
    )
  end

  defp ids(events), do: Enum.map(events, & &1.id)

  describe "suggestions/1" do
    test "lists upcoming events soonest first, then recent ones latest first" do
      later = event_in(30)
      soon = event_in(2)
      old = event_in(-40)
      recent = event_in(-3)

      suggested =
        ids(Picker.suggestions())
        |> Enum.filter(&(&1 in ids([later, soon, old, recent])))

      assert suggested == [soon.id, later.id, recent.id, old.id]
    end

    test "treats an event happening today as upcoming" do
      # Event dates are calendar days stored at midnight, which is before "now".
      today =
        event_fixture(%{
          start_date: Picker.today_start(),
          end_date: Picker.today_start() |> DateTime.add(1, :day)
        })

      yesterday = event_in(-1)

      suggested = ids(Picker.suggestions())
      upcoming_ids = Enum.take_while(suggested, &(&1 != yesterday.id))

      assert today.id in upcoming_ids
      assert Picker.upcoming?(today)

      refute Picker.upcoming?(%{
               start_date: DateTime.add(Picker.today_start(), -1, :day)
             })
    end

    test "never offers deleted events" do
      gone = event_in(5, state: :deleted)

      refute gone.id in ids(Picker.suggestions())
    end

    test "keeps unpublished events, since orders are often placed ahead of time" do
      draft = event_in(5, state: :draft, published_at: nil)

      assert draft.id in ids(Picker.suggestions())
    end

    test "returns only what the picker shows" do
      event = event_in(1)

      suggestion = Enum.find(Picker.suggestions(), &(&1.id == event.id))

      assert Map.keys(suggestion) |> Enum.sort() ==
               [:id, :start_date, :state, :title]
    end

    test "caps upcoming and recent events" do
      for day <- 1..12, do: event_in(day)
      for day <- 1..8, do: event_in(-day)

      suggestions = Picker.suggestions()

      # Split on the picker's own boundary (start of today in California), not
      # the current instant; the two differ for part of every UTC day.
      {upcoming, past} = Enum.split_with(suggestions, &Picker.upcoming?/1)

      assert length(upcoming) <= 8
      assert length(past) <= 4
    end
  end

  describe "search/2" do
    test "matches part of a title, ignoring case" do
      match = event_in(10, title: "Midsummer Gala Dinner")
      _other = event_in(10, title: "Ski Trip Kickoff")

      assert ids(Picker.search("gala")) == [match.id]
    end

    test "tolerates typos" do
      match = event_in(10, title: "Midsummer Gala Dinner")

      assert match.id in ids(Picker.search("midsumer gal"))
    end

    test "matches the reference id" do
      match = event_in(10, title: "Unrelated Name")

      assert match.id in ids(Picker.search(match.reference_id))
    end

    test "treats % and _ literally" do
      percent = event_in(10, title: "100% Wool Night")
      _other = event_in(10, title: "Wool Night")

      assert ids(Picker.search("100%")) == [percent.id]
    end

    test "never returns deleted events" do
      gone = event_in(5, title: "Cancelled Gala", state: :deleted)

      refute gone.id in ids(Picker.search("Cancelled Gala"))
    end

    test "puts an upcoming event ahead of an equally good past one" do
      past = event_in(-20, title: "Quarterly Mixer")
      upcoming = event_in(20, title: "Quarterly Mixer")

      assert ids(Picker.search("Quarterly Mixer")) == [upcoming.id, past.id]
    end

    test "ranks the closest upcoming event first among equal matches" do
      far = event_in(60, title: "Winter Social")
      near = event_in(7, title: "Winter Social")

      assert ids(Picker.search("Winter Social")) == [near.id, far.id]
    end

    test "honors the limit" do
      for _ <- 1..5, do: event_in(3, title: "Repeat Gathering")

      assert length(Picker.search("Repeat Gathering", limit: 3)) == 3
    end
  end

  describe "get/1" do
    test "returns the picker summary" do
      event = event_in(4)

      assert %{id: id, title: title} = Picker.get(event.id)
      assert id == event.id
      assert title == event.title
    end

    test "is nil for a deleted or unknown event" do
      gone = event_in(4, state: :deleted)

      assert Picker.get(gone.id) == nil
      assert Picker.get(Ecto.ULID.generate()) == nil
    end
  end
end
