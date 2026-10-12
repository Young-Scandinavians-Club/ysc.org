defmodule YscWeb.Emails.EventHelpersTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events.Event
  alias Ysc.Media.Image
  alias Ysc.Repo
  alias YscWeb.Emails.EventHelpers

  describe "require_event!/1" do
    test "returns the event struct" do
      event = event_fixture()
      assert EventHelpers.require_event!(event) == event
    end

    test "raises when the event is nil" do
      assert_raise ArgumentError, "Event cannot be nil", fn ->
        Ysc.Test.Invoke.call(EventHelpers, :require_event!, [nil])
      end
    end
  end

  describe "event_summary/2" do
    test "copies identity fields and converts HTML description to plain text" do
      event = %Event{
        id: "evt-1",
        title: "Midsummer",
        description: "<p>Hello <b>World</b></p>",
        start_date: ~U[2026-07-15 00:00:00Z],
        start_time: ~T[17:00:00],
        end_date: ~U[2026-07-15 00:00:00Z],
        end_time: ~T[20:00:00],
        location_name: "Tupper & Reed",
        address: "123 Test St",
        age_restriction: 21
      }

      summary = EventHelpers.event_summary(event)

      assert summary.id == "evt-1"
      assert summary.title == "Midsummer"
      assert summary.description == "Hello World"
      assert summary.location_name == "Tupper & Reed"
      assert summary.address == "123 Test St"
      assert summary.age_restriction == 21
      refute Map.has_key?(summary, :organizer)
    end

    test "includes organizer names when requested and the association is loaded" do
      event = %Event{
        id: "evt-1",
        title: "Midsummer",
        description: nil,
        organizer: %Ysc.Accounts.User{first_name: "Astrid", last_name: "Berg"}
      }

      summary = EventHelpers.event_summary(event, organizer: true)

      assert summary.organizer == %{first_name: "Astrid", last_name: "Berg"}
    end

    test "sets organizer to nil when the association is not loaded" do
      event = %Event{id: "evt-1", title: "Midsummer", description: nil}

      refute Ecto.assoc_loaded?(event.organizer)

      summary = EventHelpers.event_summary(event, organizer: true)
      assert summary.organizer == nil
    end

    test "honors a custom field list" do
      event = %Event{
        id: "evt-1",
        title: "Cancelled picnic",
        location_name: "Park",
        address: "1 Oak"
      }

      summary =
        EventHelpers.event_summary(event,
          fields: [:id, :title, :location_name, :address]
        )

      assert summary == %{
               id: "evt-1",
               title: "Cancelled picnic",
               location_name: "Park",
               address: "1 Oak"
             }
    end
  end

  describe "event_display/2" do
    setup do
      organizer = user_fixture()
      event = event_fixture(%{organizer_id: organizer.id})
      %{organizer: organizer, event: event}
    end

    test "builds nested event assigns with datetime and public URL", %{
      event: event,
      organizer: organizer
    } do
      event =
        event
        |> Event.changeset(%{
          start_date: ~U[2026-07-15 00:00:00Z],
          start_time: ~T[17:00:00],
          description: "July Happy Hour at Tupper &amp; Reed"
        })
        |> Repo.update!()

      display = EventHelpers.event_display(event, organizer: true)

      assert display.event.id == event.id
      assert display.event.title == event.title
      assert display.event.description == "July Happy Hour at Tupper & Reed"
      assert display.event.organizer.first_name == organizer.first_name
      assert display.event_url =~ "/events/#{event.id}"
      assert display.event_date_time =~ "July 15, 2026"
      assert display.event_date_time =~ "5:00 PM"
      assert display.event_image_url == nil
      refute Map.has_key?(display, :first_name)
    end

    test "omits event_url when disabled and does not query users", %{
      event: event
    } do
      {display, user_selects} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            EventHelpers.event_display(event,
              preload: [:cover_image],
              event_url: false,
              fields: [:id, :title, :location_name, :address]
            )
          end,
          pattern: ~r/FROM "users"/i,
          caller_pids: [self()]
        )

      assert user_selects == 0
      refute Map.has_key?(display, :event_url)

      assert display.event == %{
               id: event.id,
               title: event.title,
               location_name: event.location_name,
               address: event.address
             }
    end

    test "includes optimized cover image URL when preloaded", %{
      event: event,
      organizer: organizer
    } do
      {:ok, image} =
        %Image{
          user_id: organizer.id,
          raw_image_path: "https://example.com/raw/event.jpg",
          optimized_image_path: "https://example.com/optimized/event.jpg",
          processing_state: :completed
        }
        |> Repo.insert()

      event =
        event
        |> Event.changeset(%{image_id: image.id})
        |> Repo.update!()
        |> Repo.preload([:organizer, :cover_image])

      display = EventHelpers.event_display(event)

      assert display.event_image_url ==
               "https://example.com/optimized/event.jpg"
    end

    test "raises when the event is nil" do
      assert_raise ArgumentError, "Event cannot be nil", fn ->
        Ysc.Test.Invoke.call(EventHelpers, :event_display, [nil])
      end
    end
  end

  describe "event_headline/2" do
    test "returns a flat title payload without loading organizer users" do
      event = event_fixture()

      {headline, user_selects} =
        Ysc.QueryCounter.with_query_counter(
          fn -> EventHelpers.event_headline(event) end,
          pattern: ~r/FROM "users"/i,
          caller_pids: [self()]
        )

      assert user_selects == 0
      assert headline.event_title == event.title
      refute Map.has_key?(headline, :event)
      refute Map.has_key?(headline, :event_url)
      refute Map.has_key?(headline, :first_name)
    end
  end
end
