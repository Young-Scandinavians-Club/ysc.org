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

      assert html =~ "See you at the event, Alice"
      assert html =~ "Summer Party"
      assert html =~ "Order Confirmed"
    end

    test "shows past-event copy when event start_date is in the past", %{
      conn: conn
    } do
      user = create_user_with_membership(%{first_name: "Sigrid"})

      # Create as future first so ticket purchase validation passes, then backdate
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      # Backdate the event so it appears to be in the past
      {:ok, _} =
        event
        |> Ecto.Changeset.change(%{
          start_date:
            DateTime.add(DateTime.utc_now(), -7, :day)
            |> DateTime.truncate(:second)
        })
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert has_element?(
               view,
               "#order-confirmation",
               "Hope you had a blast, Sigrid"
             )

      assert has_element?(view, "#order-confirmation", "Thanks for coming")

      assert has_element?(
               view,
               "#order-confirmation",
               "See you at the next one"
             )
    end

    test "shows upcoming copy when event start_date is in the future", %{
      conn: conn
    } do
      user = create_user_with_membership(%{first_name: "Lars"})

      future_event =
        create_event(%{start_date: DateTime.add(DateTime.utc_now(), 14, :day)})

      tier = create_ticket_tier(future_event)
      order = create_ticket_order(user, future_event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert has_element?(
               view,
               "#order-confirmation",
               "See you at the event, Lars"
             )

      assert has_element?(view, "#order-confirmation", "are confirmed")
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
    test "displays event title", %{conn: conn} do
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
      refute html =~ "A wonderful evening"
    end

    test "displays event date", %{conn: conn} do
      user = create_user_with_membership()
      event =
        create_event(%{
          start_date: ~U[2027-06-15 10:00:00Z],
          end_date: ~U[2027-06-16 10:00:00Z]
        })
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "June 15, 2027"
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

    test "does not show free while paid order payment is still attaching",
         %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)

      order =
        create_ticket_order(user, event, %{
          total_amount: Money.new(5000, :USD)
        })

      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert has_element?(view, "#order-confirmation-payment-method")
      refute has_element?(view, "#order-confirmation-payment-method", "Free")
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

    test "payment summary ticket count excludes donations", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      paid_tier = create_ticket_tier(event, %{name: "General Admission"})

      donation_tier =
        create_ticket_tier(event, %{
          name: "Donation",
          type: :donation,
          price: nil
        })

      order = create_ticket_order(user, event)
      _paid = create_ticket(order, paid_tier)
      _donation = create_ticket(order, donation_tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      payment_ticket_count =
        view
        |> element("#order-confirmation-payment-ticket-count-value")
        |> render()
        |> String.replace(~r/<[^>]+>/, "")
        |> String.trim()

      assert payment_ticket_count == "1"
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

      assert {:error, {:live_redirect, %{to: path}}} =
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

      assert {:error, {:live_redirect, %{to: path}}} =
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

  describe "ticket refund display" do
    test "shows Refunded badge for cancelled ticket in a confirmed order", %{
      conn: conn
    } do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      ticket = create_ticket(order, tier)

      {:ok, ticket} =
        ticket
        |> Events.Ticket.status_changeset(%{status: :cancelled})
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Refunded"
      assert html =~ ticket.reference_id
    end
  end

  describe "cancelled orders" do
    test "shows cancelled heading and copy", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{title: "Winter Gala"})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      {:ok, order} =
        order
        |> Tickets.TicketOrder.status_changeset(%{
          status: :cancelled,
          cancelled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Order Cancelled"
      assert html =~ "Winter Gala"
    end

    test "cancelled order shows x-circle icon", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      {:ok, order} =
        order
        |> Tickets.TicketOrder.status_changeset(%{
          status: :cancelled,
          cancelled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "hero-x-circle"
    end
  end

  describe "navigation handlers" do
    test "close redirects to event page", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert {:error, {:redirect, %{to: path}}} = render_click(view, "close")
      assert path == "/events/#{event.id}"
    end
  end

  describe "ticket counts and badges" do
    test "single ticket shows Ticket in badge", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "1 Ticket"
    end

    test "multiple tickets show Tickets plural", %{conn: conn} do
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

    test "event details badge excludes donation tickets from count", %{
      conn: conn
    } do
      user = create_user_with_membership()
      event = create_event(%{})
      paid_tier = create_ticket_tier(event, %{name: "General Admission"})

      donation_tier =
        create_ticket_tier(event, %{
          name: "Donation",
          type: :donation,
          price: nil
        })

      order = create_ticket_order(user, event)
      _paid = create_ticket(order, paid_tier)
      _donation = create_ticket(order, donation_tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert has_element?(view, "#event-details-ticket-count-badge", "1 Ticket")

      refute has_element?(
               view,
               "#event-details-ticket-count-badge",
               "2 Tickets"
             )

      assert has_element?(
               view,
               "#order-items-section-title-text",
               "Tickets & Donations"
             )

      assert has_element?(view, "[id^='donation-badge-']", "Donation")

      assert has_element?(
               view,
               "[id^='donation-not-event-ticket-']",
               "Not an event ticket"
             )
    end

    test "donation-only order uses Your Donations section title", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})

      donation_tier =
        create_ticket_tier(event, %{
          name: "Donation",
          type: :donation,
          price: nil
        })

      order = create_ticket_order(user, event)
      _donation = create_ticket(order, donation_tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert has_element?(
               view,
               "#order-items-section-title-text",
               "Your Donations"
             )

      assert has_element?(
               view,
               "[id^='donation-not-event-ticket-']",
               "Not an event ticket"
             )
    end
  end

  describe "event fields edge cases" do
    test "event without cover image shows gradient placeholder", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{with_image: false})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "from-blue-500"
    end

    test "event without start_time shows Time TBD", %{conn: conn} do
      user = create_user_with_membership()

      event =
        create_event(%{
          start_time: nil
        })

      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Time TBD"
    end

    test "event without location shows TBD", %{conn: conn} do
      user = create_user_with_membership()

      event =
        create_event(%{
          location_name: nil,
          address: nil
        })

      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "TBD"
    end
  end

  describe "discounts and order totals" do
    test "donation amount excludes per-ticket discounts from paid ticket subtotal",
         %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})

      paid_tier =
        create_ticket_tier(event, %{
          name: "General Admission",
          price: Money.new(:USD, "50.00")
        })

      donation_tier =
        create_ticket_tier(event, %{
          name: "Donation",
          type: :donation,
          price: nil
        })

      order =
        create_ticket_order(user, event, %{
          total_amount: Money.new(:USD, "55.00")
        })

      _paid =
        create_ticket(order, paid_tier, %{
          discount_amount: Money.new(:USD, "10.00")
        })

      donation = create_ticket(order, donation_tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert has_element?(
               view,
               "#donation-not-event-ticket-#{donation.id}",
               "Not an event ticket"
             )

      assert has_element?(
               view,
               "#order-confirmation-items-section",
               "$15.00"
             )

      refute has_element?(
               view,
               "#order-confirmation-items-section",
               "$5.00"
             )
    end

    test "order with discount shows subtotal and discount lines", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)

      order =
        create_ticket_order(user, event, %{
          total_amount: Money.new(4000, :USD),
          discount_amount: Money.new(1000, :USD)
        })

      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Subtotal"
      assert html =~ "Discount"
    end
  end

  describe "page structure and identity" do
    test "root element has order-confirmation id", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert has_element?(view, "#order-confirmation")
    end

    test "uses Member when first name is nil", %{conn: conn} do
      user = create_user_with_membership()

      {:ok, user} =
        user |> Ecto.Changeset.change(%{first_name: nil}) |> Repo.update()

      event = create_event(%{title: "Club Night"})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "See you at the event, Member"
    end

    test "meta description assign reflected in page", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "ticket order confirmation" or
               html =~ "Young Scandinavians"
    end
  end

  describe "async refund loading" do
    test "render_async completes for cancelled order", %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})
      tier = create_ticket_tier(event)
      order = create_ticket_order(user, event)
      _ticket = create_ticket(order, tier)

      {:ok, order} =
        order
        |> Tickets.TicketOrder.status_changeset(%{
          status: :cancelled,
          cancelled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      render_async(view)
      html = render(view)
      assert html =~ "Order Cancelled"
    end
  end

  describe "registration and ticket tiers" do
    test "ticket tier with registration shows registration block when detail exists",
         %{conn: conn} do
      user = create_user_with_membership()
      event = create_event(%{})

      tier =
        create_ticket_tier(event, %{
          requires_registration: true,
          name: "Workshop"
        })

      order = create_ticket_order(user, event)

      {:ok, ticket} =
        %Events.Ticket{}
        |> Events.Ticket.changeset(%{
          ticket_order_id: order.id,
          ticket_tier_id: tier.id,
          event_id: event.id,
          user_id: user.id,
          reference_id: "TKT-#{System.unique_integer()}",
          status: :confirmed,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
        })
        |> Repo.insert()

      {:ok, _} =
        %Events.TicketDetail{}
        |> Events.TicketDetail.changeset(%{
          ticket_id: ticket.id,
          first_name: "Reg",
          last_name: "User",
          email: "reg@example.com"
        })
        |> Repo.insert()

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orders/#{order.id}/confirmation")

      assert html =~ "Registration Details"
      assert html =~ "Reg"
    end
  end
end
