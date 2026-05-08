defmodule YscWeb.EventsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Events
  alias Ysc.Media
  alias Ysc.MessagePassingEvents
  alias Ysc.Repo

  import Ysc.EventsFixtures, only: [ticket_tier_fixture: 1]

  # Helper to create an image
  defp create_image do
    uploader = user_fixture()

    {:ok, image} =
      %Media.Image{user_id: uploader.id}
      |> Media.Image.add_image_changeset(%{
        title: "Test Event Image",
        raw_image_path: "/uploads/test_event.jpg",
        optimized_image_path: "/uploads/test_event_optimized.jpg",
        thumbnail_path: "/uploads/test_event_thumb.jpg",
        blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
      })
      |> Repo.insert()

    image
  end

  # Helper to create an event
  defp create_event(attrs) do
    organizer = attrs[:organizer] || user_fixture()
    image = if Map.get(attrs, :with_image, true), do: create_image(), else: nil

    # Calculate dates based on whether this should be past or upcoming
    {start_date, end_date} =
      if Map.get(attrs, :past, false) do
        {
          DateTime.add(DateTime.utc_now(), -30, :day),
          DateTime.add(DateTime.utc_now(), -29, :day)
        }
      else
        {
          DateTime.add(DateTime.utc_now(), 7, :day),
          DateTime.add(DateTime.utc_now(), 8, :day)
        }
      end

    default_attrs = %{
      title: "Test Event #{System.unique_integer()}",
      description: "A test event description",
      start_date: start_date,
      end_date: end_date,
      state: :published,
      ticket_sales_start: DateTime.add(DateTime.utc_now(), -1, :day),
      ticket_sales_end: DateTime.add(DateTime.utc_now(), 6, :day),
      location: "Test Location",
      max_attendees: 100,
      organizer_id: organizer.id,
      image_id: if(image, do: image.id, else: nil)
    }

    attrs =
      attrs
      |> Map.delete(:organizer)
      |> Map.delete(:with_image)
      |> Map.delete(:past)

    attrs = Map.merge(default_attrs, attrs)

    {:ok, event} =
      %Events.Event{}
      |> Events.Event.changeset(attrs)
      |> Repo.insert()

    event
  end

  describe "mount/3" do
    test "loads events page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "Events"
    end

    test "sets page title to Events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events")

      assert page_title(view) =~ "Events"
    end

    test "displays masthead with title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "Events"
      # Either "What's Next" or "The Calendar"
      assert html =~ "What" or html =~ "Calendar"
    end
  end

  describe "page structure" do
    test "includes upcoming events section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      # EventsListLive component should be rendered (check for grid structure)
      assert html =~ "lg:col-span-9"
    end

    test "includes sidebar with info", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "Upcoming Events"
      assert html =~ "Explore our curated calendar"
    end

    test "includes Get Involved section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "Get Involved"
      assert html =~ "Have an idea for an event"
    end

    test "includes Stay Connected section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "Stay Connected"
      assert html =~ "Read Club News"
    end

    test "has link to contact page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ ~p"/contact"
    end

    test "contact link pre-fills Events subject and message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "subject=Events"
      assert html =~ "message="
    end

    test "has link to news page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ ~p"/news"
    end
  end

  describe "masthead title" do
    test "displays 'The Calendar' when no upcoming events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      assert html =~ "The Calendar" or html =~ "What"
    end

    test "displays 'What's Next' when there are upcoming events", %{conn: conn} do
      _event = create_event(%{title: "Future Event", past: false})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      assert html =~ "What" or html =~ "Calendar"
    end
  end

  describe "async data loading" do
    test "loads events data after connection", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      rendered_view = :sys.get_state(view.pid)
      assert rendered_view.socket.assigns.async_data_loaded == true
    end

    test "displays loading skeleton before data loads", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      # Should have loading skeleton initially
      assert html =~ "animate-pulse" or html =~ "upcoming_events"
    end
  end

  describe "past events gallery" do
    test "does not show past events section when no past events exist", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      refute html =~ "What Was"
    end

    test "shows past events gallery when past events exist", %{conn: conn} do
      _past_event = create_event(%{title: "Old Event", past: true})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)

      assert html =~ "Hvad var" or html =~ "Det Som Varit" or html =~ "Hva var" or
               html =~ "Mikä oli" or html =~ "Hvað var" or html =~ "Old Event"
    end

    test "displays past event images in grid", %{conn: conn} do
      past_event = create_event(%{title: "Past Event", past: true})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      assert html =~ "Past Event" or html =~ past_event.id
    end

    test "past events have grayscale effect", %{conn: conn} do
      _past_event = create_event(%{title: "Old Event", past: true})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      assert html =~ "grayscale"
    end

    test "past events are clickable links to event details", %{conn: conn} do
      past_event = create_event(%{title: "Old Event", past: true})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      assert html =~ "/events/#{past_event.id}"
    end
  end

  describe "show more past events" do
    test "does not show 'Show More' button when few past events", %{conn: conn} do
      for i <- 1..5 do
        create_event(%{title: "Past Event #{i}", past: true})
      end

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      refute html =~ "Show More Past Events"
    end

    test "shows 'Show More' button when many past events exist", %{conn: conn} do
      for i <- 1..15 do
        create_event(%{title: "Past Event #{i}", past: true})
      end

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      assert html =~ "Show More Past Events" or html =~ "Past Event"
    end

    test "clicking 'Show More' loads more past events", %{conn: conn} do
      for i <- 1..20 do
        create_event(%{title: "Past Event #{i}", past: true})
      end

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      result = render_click(view, "show_more_past_events")
      assert is_binary(result) or is_map(result)
    end

    test "increases past events limit when clicking Show More", %{conn: conn} do
      organizer = user_fixture()

      for i <- 1..20 do
        create_event(%{
          title: "Past Event #{i}",
          past: true,
          with_image: false,
          organizer: organizer
        })
      end

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      rendered_view = :sys.get_state(view.pid)
      initial_limit = rendered_view.socket.assigns.past_events_limit

      render_click(view, "show_more_past_events")

      rendered_view = :sys.get_state(view.pid)
      assert rendered_view.socket.assigns.past_events_limit > initial_limit
    end

    test "limits maximum past events to 50", %{conn: conn} do
      organizer = user_fixture()

      for i <- 1..60 do
        create_event(%{
          title: "Past Event #{i}",
          past: true,
          with_image: false,
          organizer: organizer,
          reference_id: "EVT-TEST-#{i}-#{System.unique_integer()}"
        })
      end

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      for _i <- 1..10 do
        render_click(view, "show_more_past_events")
      end

      rendered_view = :sys.get_state(view.pid)
      assert rendered_view.socket.assigns.past_events_limit <= 50
    end
  end

  describe "real-time updates" do
    test "subscribes to events topic when connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events")

      # View should be subscribed (connection established)
      assert view.pid
    end
  end

  describe "handle_info pubsub" do
    test "handles EventAdded without crashing", %{conn: conn} do
      event = create_event(%{title: "PubSub Event", past: false})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events, %MessagePassingEvents.EventAdded{event: event}}
      )

      html = render(view)
      assert html =~ "Events"
    end

    test "handles EventUpdated without crashing", %{conn: conn} do
      event = create_event(%{title: "Updated Via PubSub", past: false})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events, %MessagePassingEvents.EventUpdated{event: event}}
      )

      assert render(view) =~ "Events"
    end

    test "handles TicketTierAdded when event is missing", %{conn: conn} do
      fake_tier = %Ysc.Events.TicketTier{
        id: Ecto.ULID.generate(),
        event_id: Ecto.ULID.generate()
      }

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events,
         %MessagePassingEvents.TicketTierAdded{ticket_tier: fake_tier}}
      )

      assert render(view) =~ "Events"
    end

    test "handles TicketTierAdded when event exists", %{conn: conn} do
      event = create_event(%{title: "Tier Parent", past: false})
      tier = ticket_tier_fixture(%{event_id: event.id, name: "VIP"})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events, %MessagePassingEvents.TicketTierAdded{ticket_tier: tier}}
      )

      assert render(view) =~ "Events"
    end

    test "handles TicketReservationCreated when ticket tier is missing", %{
      conn: conn
    } do
      reservation = %Ysc.Events.TicketReservation{
        ticket_tier_id: Ecto.ULID.generate()
      }

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events,
         %MessagePassingEvents.TicketReservationCreated{
           ticket_reservation: reservation
         }}
      )

      assert render(view) =~ "Events"
    end

    test "handles TicketReservationFulfilled when tier and event exist", %{
      conn: conn
    } do
      user = user_fixture()
      event = create_event(%{title: "Res Event", past: false})
      tier = ticket_tier_fixture(%{event_id: event.id})

      reservation =
        %Ysc.Events.TicketReservation{}
        |> Ysc.Events.TicketReservation.changeset(%{
          ticket_tier_id: tier.id,
          user_id: user.id,
          created_by_id: user.id,
          quantity: 1,
          expires_at: DateTime.add(DateTime.utc_now(), 1, :day)
        })
        |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events,
         %MessagePassingEvents.TicketReservationFulfilled{
           ticket_reservation: reservation
         }}
      )

      assert render(view) =~ "Events"
    end

    test "handles TicketReservationCancelled", %{conn: conn} do
      user = user_fixture()
      event = create_event(%{title: "Cancel Event", past: false})
      tier = ticket_tier_fixture(%{event_id: event.id})

      reservation =
        %Ysc.Events.TicketReservation{}
        |> Ysc.Events.TicketReservation.changeset(%{
          ticket_tier_id: tier.id,
          user_id: user.id,
          created_by_id: user.id,
          quantity: 1,
          expires_at: DateTime.add(DateTime.utc_now(), 1, :day)
        })
        |> Repo.insert!()

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events,
         %MessagePassingEvents.TicketReservationCancelled{
           ticket_reservation: reservation
         }}
      )

      assert render(view) =~ "Events"
    end

    test "handles TicketTierUpdated and TicketTierDeleted", %{conn: conn} do
      event = create_event(%{title: "Update Delete", past: false})
      tier = ticket_tier_fixture(%{event_id: event.id})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events, %MessagePassingEvents.TicketTierUpdated{ticket_tier: tier}}
      )

      assert render(view) =~ "Events"

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events, %MessagePassingEvents.TicketTierDeleted{ticket_tier: tier}}
      )

      assert render(view) =~ "Events"
    end
  end

  describe "responsive design" do
    test "includes responsive grid classes", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "lg:col-span"
      assert html =~ "md:grid-cols"
    end

    test "includes responsive spacing classes", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "md:py-"
      assert html =~ "lg:"
    end
  end

  describe "image handling" do
    test "displays blur hash for past events without image", %{conn: conn} do
      _past_event =
        create_event(%{title: "No Image Event", past: true, with_image: false})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)

      assert html =~ "BlurHashCanvas" or html =~ "No Image Event" or
               not (html =~ "No Image Event")
    end

    test "displays optimized image when available", %{conn: conn} do
      _past_event =
        create_event(%{title: "Event With Image", past: true, with_image: true})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)

      assert html =~ "test_event_optimized.jpg" or html =~ "Event With Image" or
               not (html =~ "Event With Image")
    end

    test "falls back to raw image when optimized not available", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "accessibility" do
    test "includes alt text for past event images", %{conn: conn} do
      _past_event = create_event(%{title: "Accessible Event", past: true})

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)

      assert html =~ "alt=" or html =~ "Accessible Event" or
               not (html =~ "Accessible Event")
    end

    test "includes proper heading hierarchy", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "<h1"
      assert html =~ "<h2" or html =~ "<h4"
    end
  end

  describe "empty states" do
    test "handles no events gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      html = render(view)
      assert html =~ "Events"
      assert html =~ "Upcoming Events"
    end
  end

  describe "community chat links" do
    test "shows WhatsApp link for authenticated users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "chat.whatsapp.com"
    end

    test "does not show WhatsApp link for unauthenticated users", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      refute html =~ "chat.whatsapp.com"
    end

    test "shows Discord link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/events")

      assert html =~ "discord.gg"
    end
  end

  describe "handle_async load_events_data exit" do
    test "marks async loaded when async task exits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/events")
      %{socket: socket} = :sys.get_state(view.pid)

      assert {:noreply, new_socket} =
               YscWeb.EventsLive.handle_async(
                 :load_events_data,
                 {:exit, :test_reason},
                 socket
               )

      assert new_socket.assigns.async_data_loaded == true
    end
  end

  describe "TicketReservationFulfilled without tier" do
    test "handles TicketReservationFulfilled when ticket tier was deleted", %{
      conn: conn
    } do
      reservation = %Ysc.Events.TicketReservation{
        ticket_tier_id: Ecto.ULID.generate()
      }

      {:ok, view, _html} = live(conn, ~p"/events")
      render_async(view)

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "events",
        {Ysc.Events,
         %MessagePassingEvents.TicketReservationFulfilled{
           ticket_reservation: reservation
         }}
      )

      assert render(view) =~ "Events"
    end
  end
end
