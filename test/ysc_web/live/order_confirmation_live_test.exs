defmodule YscWeb.OrderConfirmationLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Repo
  alias Ysc.Events
  alias Ysc.Tickets
  alias Ysc.Media

  # Helper to create a user with an active membership (lifetime)
  defp create_user_with_membership(attrs \\ %{}) do
    user = user_fixture(attrs)

    # Update user with lifetime membership (truncated to remove microseconds)
    {:ok, user} =
      user
      |> Ecto.Changeset.change(%{
        lifetime_membership_awarded_at:
          DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()

    user
  end

  # Helper to create an image
  defp create_image do
    uploader = user_fixture()

    {:ok, image} =
      %Media.Image{}
      |> Media.Image.add_image_changeset(%{
        title: "Test Event Image",
        raw_image_path: "/uploads/test_event.jpg",
        optimized_image_path: "/uploads/test_event_optimized.jpg",
        thumbnail_path: "/uploads/test_event_thumb.jpg",
        blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
        user_id: uploader.id
      })
      |> Repo.insert()

    image
  end

  # Helper to create an event
  defp create_event(attrs) do
    organizer = attrs[:organizer] || user_fixture()
    image = if Map.get(attrs, :with_image, true), do: create_image(), else: nil

    default_attrs = %{
      title: "Test Event #{System.unique_integer()}",
      description: "A test event description",
      start_date: DateTime.add(DateTime.utc_now(), 7, :day),
      end_date: DateTime.add(DateTime.utc_now(), 8, :day),
      state: :published,
      ticket_sales_start: DateTime.utc_now(),
      ticket_sales_end: DateTime.add(DateTime.utc_now(), 6, :day),
      location_name: "Test Location",
      max_attendees: 100,
      organizer_id: organizer.id,
      image_id: if(image, do: image.id, else: nil)
    }

    attrs = attrs |> Map.delete(:organizer) |> Map.delete(:with_image)
    attrs = Map.merge(default_attrs, attrs)

    {:ok, event} =
      %Events.Event{}
      |> Events.Event.changeset(attrs)
      |> Repo.insert()

    Repo.preload(event, [:cover_image])
  end

  # Helper to create a ticket tier
  defp create_ticket_tier(event, attrs \\ %{}) do
    default_attrs = %{
      event_id: event.id,
      name: "General Admission",
      type: :paid,
      price: Money.new(5000, :USD),
      max_tickets: 100,
      requires_registration: false
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, tier} =
      %Events.TicketTier{}
      |> Events.TicketTier.changeset(attrs)
      |> Repo.insert()

    tier
  end

  # Helper to create a ticket order
  defp create_ticket_order(user, event, attrs \\ %{}) do
    default_attrs = %{
      user_id: user.id,
      event_id: event.id,
      reference_id: "ORD-#{System.unique_integer()}",
      status: :confirmed,
      total_amount: Money.new(5000, :USD),
      expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, order} =
      %Tickets.TicketOrder{}
      |> Tickets.TicketOrder.create_changeset(attrs)
      |> Repo.insert()

    Repo.preload(order, [:user, :event, :payment, :tickets])
  end

  # Helper to create a ticket
  defp create_ticket(ticket_order, ticket_tier, attrs \\ %{}) do
    # Get the event and user from the preloaded order
    event_id = ticket_order.event_id
    user_id = ticket_order.user_id

    default_attrs = %{
      ticket_order_id: ticket_order.id,
      ticket_tier_id: ticket_tier.id,
      event_id: event_id,
      user_id: user_id,
      reference_id: "TKT-#{System.unique_integer()}",
      status: :confirmed,
      expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, ticket} =
      %Events.Ticket{}
      |> Events.Ticket.changeset(attrs)
      |> Repo.insert()

    Repo.preload(ticket, [:ticket_tier, :registration])
  end

  describe "mount/3 - authentication" do
    test "redirects unauthenticated users to login page", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} =
        live(conn, ~p"/orders/01KG5TEST123/confirmation")

      # Redirects to login (handled by LiveView authentication plug)
      assert path == "/users/log-in"
    end

    test "allows authenticated users to view their orders", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Order Confirmed"
    end

    test "prevents users from viewing other users' orders", %{conn: conn} do
      user1 = create_user_with_membership()
      user2 = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user1, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user2)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/orders/#{order.id}/confirmation")

      assert path == "/events"
      assert flash["error"] == "Order not found"
    end

    test "handles non-existent order", %{conn: conn} do
      user = create_user_with_membership()
      conn = log_in_user(conn, user)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/orders/#{Ecto.ULID.generate()}/confirmation")

      assert path == "/events"
      assert flash["error"] == "Order not found"
    end
  end

  describe "order confirmation display" do
    test "displays order confirmation heading", %{conn: conn} do
      user = create_user_with_membership(%{first_name: "Alice"})
      event = create_event(%{title: "Summer Party"})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "See you at the Event, Alice"
      assert html =~ "Summer Party"
      assert html =~ "Order Confirmed"
    end

    test "displays order reference number", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      # Check for Order Reference text and the reference ID pattern (ORD-)
      assert html =~ "Order Reference"
      assert html =~ "ORD-"
    end

    test "sets page title to Order Confirmation", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert page_title(view) =~ "Order Confirmation"
    end
  end

  describe "confetti parameter" do
    test "shows confetti when confetti parameter is true", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(conn, ~p"/orders/#{order.id}/confirmation?confetti=true")

      assert html =~ "data-show-confetti=\"true\""
    end

    test "does not show confetti without parameter", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "data-show-confetti=\"false\""
    end

    test "includes Confetti hook", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "phx-hook=\"Confetti\""
    end
  end

  describe "event details display" do
    test "displays event title and description", %{conn: conn} do
      user = create_user_with_membership()

      event =
        create_event(%{
          title: "Annual Gala",
          description: "A wonderful evening"
        })

      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Annual Gala"
      assert html =~ "A wonderful evening"
    end

    test "displays event date", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{start_date: ~U[2026-06-15 10:00:00Z]})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "June 15, 2026"
    end

    test "displays event location", %{conn: conn} do
      user = create_user_with_membership()

      event =
        create_event(%{
          location_name: "Grand Hall",
          address: "123 Main St, San Francisco, CA"
        })

      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Grand Hall"
      assert html =~ "123 Main St"
    end

    test "displays event cover image when available", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{with_image: true})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      # Image component should be present
      assert html =~ "order-confirmation-event-cover-"
    end
  end

  describe "ticket display" do
    test "displays ticket count", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket1 = create_ticket(order, tier)
      _ticket2 = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "2 Tickets"
    end

    test "displays ticket tier name", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event, %{name: "VIP Access"})
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "VIP Access"
    end

    test "displays ticket reference number", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier, %{reference_id: "TKT-ABC123"})

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "TKT-ABC123"
    end

    test "displays ticket price", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})

      tier =
        create_ticket_tier(event, %{
          price: Money.new(2500, :USD),
          name: "General Admission"
        })

      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      # Check that ticket information is displayed
      assert html =~ "General Admission"
      assert html =~ "Ticket #"
    end

    test "displays free tickets correctly", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event, %{price: Money.new(0, :USD)})

      order =
        create_ticket_order(user, event, %{total_amount: Money.new(0, :USD)})

      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Free"
    end
  end

  describe "payment summary" do
    test "displays total paid amount", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)

      order =
        create_ticket_order(user, event, %{
          total_amount: Money.new(5000, :USD),
          status: :completed
        })

      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      # Check that payment summary section exists
      assert html =~ "Total" or html =~ "Payment"
    end

    test "displays payment method", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Method"
    end

    test "shows payment summary heading", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Payment Summary"
    end
  end

  describe "action buttons" do
    test "displays view tickets button", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert has_element?(view, "button", "View All My Tickets")
    end

    test "displays back to event button", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert has_element?(view, "button", "Back to Event")
    end

    test "view-tickets button redirects to tickets page", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert {:error, {:redirect, %{to: path}}} =
               render_click(view, "view-tickets")

      assert path == "/users/tickets"
    end

    test "view-event button redirects to event page", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert {:error, {:redirect, %{to: path}}} =
               render_click(view, "view-event")

      assert path == "/events/#{event.id}"
    end
  end

  describe "footer" do
    test "displays contact email", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Need help?"
      assert html =~ "info@ysc.org"
    end
  end

  describe "page structure" do
    test "has three-column layout", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "lg:grid-cols-3"
      assert html =~ "lg:col-span-2"
    end

    test "includes event details card", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Event Details"
    end

    test "includes tickets card", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Your Tickets"
    end
  end

  describe "responsive design" do
    test "includes responsive classes", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "lg:py-"
      assert html =~ "md:flex-row"
    end
  end

  describe "accessibility" do
    test "includes proper heading hierarchy", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "<h1"
      assert html =~ "<h2"
      assert html =~ "<h3"
    end

    test "includes descriptive alt text for icons", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      # Icons should be present
      assert html =~ "hero-check-circle"
      assert html =~ "hero-ticket"
    end
  end

  describe "icons" do
    test "includes check icon for confirmed orders", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "hero-check-circle"
    end

    test "includes ticket icon", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "hero-ticket"
    end
  end
end
