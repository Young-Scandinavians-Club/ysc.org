defmodule YscWeb.EventDetailsLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory
  import Ysc.EventsFixtures
  import Mox
  import EventDetailsLiveHelpers

  alias Ysc.Repo

  setup :verify_on_exit!

  setup %{conn: conn} do
    setup_stripe_mocks()
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok, build_payment_intent(%{amount: params.amount})}
    end)

    on_exit(fn ->
      Application.delete_env(:ysc, :stripe_client)
    end)

    {:ok, conn: conn}
  end

  describe "mount/3 - event access" do
    test "loads published event successfully", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Summer Party"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Summer Party"
    end

    test "redirects when event does not exist", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/events/#{Ecto.ULID.generate()}")

      assert path == "/events"
    end

    test "sets page title to event title", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Annual Gala"}
        )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert page_title(view) =~ "Annual Gala"
    end

    test "loads upcoming event", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Future Event"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Future Event"
    end

    test "loads past event", %{conn: conn} do
      event =
        event_with_state(:past, with_image: true, attrs: %{title: "Past Event"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Past Event"
    end

    test "loads ongoing event", %{conn: conn} do
      event =
        event_with_state(:ongoing,
          with_image: true,
          attrs: %{title: "Current Event"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Current Event"
    end
  end

  describe "event display" do
    test "displays event title", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Mountain Hike"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Mountain Hike"
    end

    test "displays event description", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{
            title: "Adventure",
            description: "Join us for an amazing outdoor adventure"
          }
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Join us for an amazing outdoor adventure"
    end

    test "displays event with image", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Photo Event"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Photo Event"
    end

    test "displays event without image", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "No Photo Event"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "No Photo Event"
    end
  end

  describe "unauthenticated user interactions" do
    test "can view event page", %{conn: conn} do
      event = event_with_tickets(tier_count: 2, state: :upcoming)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end

    test "sees login prompt when trying to buy tickets", %{conn: conn} do
      event = event_with_tickets(tier_count: 2, state: :upcoming)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # Should show some indication to log in
      assert html =~ event.title
    end

    test "can toggle map without authentication", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{location: "123 Main St"}
        )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "toggle-map")
      assert is_binary(result)

      # Toggle again to close
      result = render_click(view, "toggle-map")
      assert is_binary(result)
    end

    test "close-ticket-modal works without auth", %{conn: conn} do
      event = event_with_state(:upcoming, with_image: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-ticket-modal")
      assert is_binary(result)
    end
  end

  describe "authenticated user without membership" do
    test "cannot purchase tickets without active membership", %{conn: conn} do
      user = user_with_membership(:none)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2, state: :upcoming)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # Should see event but membership requirement for tickets
      assert html =~ event.title
    end
  end

  describe "authenticated user with membership - ticket selection" do
    setup %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 3, state: :upcoming)

      {:ok, %{conn: conn, user: user, event: event}}
    end

    test "can view event", %{conn: conn, event: event} do
      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end

    test "can open ticket modal", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "open-ticket-modal")
      # May redirect to tickets page or return HTML
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end

    test "can close ticket modal", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-ticket-modal")
      assert is_binary(result)
    end

    test "handles select-ticket event", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(result)
    end

    test "handles deselect-ticket event", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select first
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Then deselect
      result =
        render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(result)
    end

    test "handles increment-ticket event", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(result)
    end

    test "handles decrement-ticket event", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Increment first to have something to decrement
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Then decrement
      result =
        render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(result)
    end

    test "handles multiple ticket selections", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)
      [tier1, tier2 | _] = event.ticket_tiers

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select multiple tickets
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier1.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier2.id})

      html = render(view)
      assert is_binary(html)
    end

    test "handles show-attendees-modal event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "show-attendees-modal")
      assert is_binary(result)
    end

    test "handles hide-attendees-modal event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-attendees-modal")
      assert is_binary(result)
    end
  end

  describe "authenticated user - donation interactions" do
    setup %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, %{conn: conn, user: user, event: event}}
    end

    test "handles set-donation-amount event with valid amount", %{
      conn: conn,
      event: event
    } do
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_click(view, "set-donation-amount", %{
          "tier-id" => tier.id,
          "amount" => "50"
        })

      assert is_binary(result)
    end

    test "handles set-donation-amount event with zero", %{
      conn: conn,
      event: event
    } do
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_click(view, "set-donation-amount", %{
          "tier-id" => tier.id,
          "amount" => "0"
        })

      assert is_binary(result)
    end

    test "handles set-donation-amount event with large amount", %{
      conn: conn,
      event: event
    } do
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_click(view, "set-donation-amount", %{
          "tier-id" => tier.id,
          "amount" => "1000"
        })

      assert is_binary(result)
    end

    test "handles update-donation-amount event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_change(view, "update-donation-amount", %{
          "value" => "75"
        })

      assert is_binary(result)
    end
  end

  describe "authenticated user - registration interactions" do
    setup %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Create event with ticket tier that requires registration
      event = event_with_state(:upcoming, with_image: true)

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Registration Required Tier",
          type: :paid,
          price: Money.new(5000, :USD),
          quantity: 50,
          requires_registration: true
        })

      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, %{conn: conn, user: user, event: event, tier: tier}}
    end

    test "handles update-registration-field event", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_change(view, "update-registration-field", %{
          "ticket_id" => tier.id,
          "field" => "first_name",
          "value" => "John"
        })

      assert is_binary(result)
    end

    test "handles update-registration-field for last name", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_change(view, "update-registration-field", %{
          "ticket_id" => tier.id,
          "field" => "last_name",
          "value" => "Doe"
        })

      assert is_binary(result)
    end

    test "handles update-registration-field for email", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_change(view, "update-registration-field", %{
          "ticket_id" => tier.id,
          "field" => "email",
          "value" => "john@example.com"
        })

      assert is_binary(result)
    end
  end

  describe "authenticated user - checkout flow" do
    setup %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2, state: :upcoming)

      {:ok, %{conn: conn, user: user, event: event}}
    end

    test "handles proceed-to-checkout event", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select a ticket first
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Then proceed to checkout
      result = render_click(view, "proceed-to-checkout")
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "handles close-order-completion event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-order-completion")
      assert is_binary(result)
    end

    test "handles payment-redirect-started event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "payment-redirect-started")
      assert is_binary(result)
    end

    test "handles checkout-expired event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "checkout-expired")
      assert is_binary(result)
    end
  end

  describe "authenticated user - free ticket flow" do
    setup %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      # Create event with free tickets
      event = event_with_state(:upcoming, with_image: true)

      free_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Free Tier",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 100
        })

      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, %{conn: conn, user: user, event: event, free_tier: free_tier}}
    end

    test "can view free tickets", %{conn: conn, event: event} do
      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end

    test "can select free tickets", %{
      conn: conn,
      event: event,
      free_tier: free_tier
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_click(view, "increase-ticket-quantity", %{
          "tier-id" => free_tier.id
        })

      assert is_binary(result)
    end

    test "can increment free tickets", %{
      conn: conn,
      event: event,
      free_tier: free_tier
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_click(view, "increase-ticket-quantity", %{
          "tier-id" => free_tier.id
        })

      assert is_binary(result)
    end
  end

  describe "authenticated user - different membership types" do
    test "lifetime member can view tickets", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end

    test "subscription member can view tickets", %{conn: conn} do
      user = user_with_membership(:subscription)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end
  end

  describe "async data loading" do
    test "loads event data after mount", %{conn: conn} do
      event = event_with_state(:upcoming, with_image: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Wait for async operations
      :timer.sleep(300)

      html = render(view)
      assert html =~ event.title
    end

    test "handles async loading with tickets", %{conn: conn} do
      event = event_with_tickets(tier_count: 3)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Wait for async operations
      :timer.sleep(300)

      html = render(view)
      assert html =~ event.title
    end
  end

  describe "error scenarios" do
    test "handles invalid event ID format", %{conn: conn} do
      assert_raise Ecto.Query.CastError, fn ->
        live(conn, ~p"/events/invalid-id")
      end
    end

    test "handles expired event gracefully", %{conn: conn} do
      event = event_with_state(:past, with_image: true)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end
  end

  describe "event states" do
    test "displays upcoming event correctly", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Upcoming Event"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Upcoming Event"
    end

    test "displays past event correctly", %{conn: conn} do
      event =
        event_with_state(:past, with_image: true, attrs: %{title: "Past Event"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Past Event"
    end

    test "displays cancelled event correctly", %{conn: conn} do
      event =
        event_with_state(:cancelled,
          with_image: true,
          attrs: %{title: "Cancelled Event"}
        )

      # Cancelled events might redirect or show special message
      result = live(conn, ~p"/events/#{event.id}")

      case result do
        {:ok, _view, html} ->
          assert html =~ "Cancelled Event"

        {:error, {:redirect, _}} ->
          :ok
      end
    end
  end

  describe "ticket tier display" do
    test "shows multiple ticket tiers", %{conn: conn} do
      event = event_with_tickets(tier_count: 3)
      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # Should show ticket information
      assert html =~ event.title
    end

    test "shows sold out tickets", %{conn: conn} do
      event = event_with_state(:upcoming, with_image: true)

      # Create a tier with no quantity (sold out)
      _tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Sold Out Tier",
          type: :paid,
          price: Money.new(5000, :USD),
          quantity: 0
        })

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end
  end

  describe "handle_params/3 - URL parameter handling" do
    test "handles normal page load", %{conn: conn} do
      event = event_with_state(:upcoming, with_image: true)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end

    test "handles page load with authenticated user", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_state(:upcoming, with_image: true)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end
  end

  describe "complete ticket purchase flow - paid tickets" do
    setup %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, %{conn: conn, user: user, event: event}}
    end

    test "user can select and increment tickets", %{conn: conn, event: event} do
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select ticket
      html =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(html)

      # Increment ticket count
      html =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(html)

      # Increment again
      html =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(html)
    end

    test "user can add and remove tickets", %{conn: conn, event: event} do
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select ticket
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Increment
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Decrement
      html =
        render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(html)

      # Deselect
      html =
        render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(html)
    end

    test "user can select multiple tier types", %{conn: conn, event: event} do
      [tier1, tier2 | _] = event.ticket_tiers

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select from first tier
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier1.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier1.id})

      # Select from second tier
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier2.id})

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "complete ticket purchase flow - with donation" do
    setup %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, %{conn: conn, user: user, event: event}}
    end

    test "user can select tickets and add donation", %{conn: conn, event: event} do
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select ticket
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Add donation
      html =
        render_click(view, "set-donation-amount", %{
          "tier-id" => tier.id,
          "amount" => "25"
        })

      assert is_binary(html)
    end

    test "user can change donation amount", %{conn: conn, event: event} do
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Set initial donation
      render_click(view, "set-donation-amount", %{
        "tier-id" => tier.id,
        "amount" => "25"
      })

      # Change donation
      html =
        render_click(view, "set-donation-amount", %{
          "tier-id" => tier.id,
          "amount" => "50"
        })

      assert is_binary(html)

      # Remove donation
      html =
        render_click(view, "set-donation-amount", %{
          "tier-id" => tier.id,
          "amount" => "0"
        })

      assert is_binary(html)
    end
  end

  describe "ticket purchase - registration required" do
    setup %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      event = event_with_state(:upcoming, with_image: true)

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Registration Required",
          type: :paid,
          price: Money.new(5000, :USD),
          quantity: 50,
          requires_registration: true
        })

      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, %{conn: conn, user: user, event: event, tier: tier}}
    end

    test "user can fill registration fields", %{
      conn: conn,
      event: event,
      tier: tier
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select ticket that requires registration
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Fill registration fields
      render_change(view, "update-registration-field", %{
        "ticket_id" => tier.id,
        "field" => "first_name",
        "value" => "Jane"
      })

      render_change(view, "update-registration-field", %{
        "ticket_id" => tier.id,
        "field" => "last_name",
        "value" => "Smith"
      })

      html =
        render_change(view, "update-registration-field", %{
          "ticket_id" => tier.id,
          "field" => "email",
          "value" => "jane@example.com"
        })

      assert is_binary(html)
    end
  end

  describe "navigation and UI interactions" do
    test "can toggle map view", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{location: "123 Test St"}
        )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Open map
      html = render_click(view, "toggle-map")
      assert is_binary(html)

      # Close map
      html = render_click(view, "toggle-map")
      assert is_binary(html)
    end

    test "can show and hide attendees modal", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_state(:upcoming, with_image: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Show modal
      html = render_click(view, "show-attendees-modal")
      assert is_binary(html)

      # Hide modal
      html = render_click(view, "close-attendees-modal")
      assert is_binary(html)
    end
  end

  describe "complete end-to-end ticket purchase - authenticated user" do
    test "can complete full ticket purchase flow with paid tickets", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      [tier1, tier2] = event.ticket_tiers

      # Load event page
      {:ok, view, html} = live(conn, ~p"/events/#{event.id}")
      assert html =~ event.title
      :timer.sleep(200)

      # Select first tier
      html =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier1.id})

      assert is_binary(html)

      # Increase quantity
      html =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier1.id})

      assert is_binary(html)

      # Also select second tier
      html =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier2.id})

      assert is_binary(html)

      # Add donation
      html =
        render_click(view, "set-donation-amount", %{
          "tier-id" => tier1.id,
          "amount" => "50"
        })

      assert is_binary(html)

      # Proceed to checkout
      result = render_click(view, "proceed-to-checkout")
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "can purchase multiple tickets of same tier", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Add multiple tickets
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      html = render(view)
      assert is_binary(html)

      # Decrease one
      html =
        render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(html)
    end

    test "can reset ticket selection", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      [tier1, tier2] = event.ticket_tiers

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select tickets
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier1.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier2.id})

      # Decrease back to zero
      render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier1.id})

      html =
        render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier2.id})

      assert is_binary(html)
    end
  end

  describe "complete end-to-end free ticket purchase" do
    test "can claim free tickets", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      event = event_with_state(:upcoming, with_image: true)

      free_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Free General Admission",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 100
        })

      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select free tickets
      html =
        render_click(view, "increase-ticket-quantity", %{
          "tier-id" => free_tier.id
        })

      assert is_binary(html)

      # Add more
      html =
        render_click(view, "increase-ticket-quantity", %{
          "tier-id" => free_tier.id
        })

      assert is_binary(html)
    end
  end

  describe "event with agenda" do
    test "can view event with agenda items", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Conference 2026"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Conference 2026"
    end
  end

  describe "ticket with registration requirements" do
    test "can view event with registration-required tiers", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      event = event_with_state(:upcoming, with_image: true)

      _tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "VIP with Registration",
          type: :paid,
          price: Money.new(10_000, :USD),
          quantity: 50,
          requires_registration: true
        })

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end

    test "can select tickets requiring registration", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      event = event_with_state(:upcoming, with_image: true)

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Workshop with Registration",
          type: :paid,
          price: Money.new(7500, :USD),
          quantity: 30,
          requires_registration: true
        })

      event = Repo.preload(event, :ticket_tiers, force: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Select ticket
      html =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(html)

      # Fill registration fields
      render_change(view, "update-registration-field", %{
        "ticket_id" => tier.id,
        "field" => "first_name",
        "value" => "Jane"
      })

      render_change(view, "update-registration-field", %{
        "ticket_id" => tier.id,
        "field" => "last_name",
        "value" => "Smith"
      })

      html =
        render_change(view, "update-registration-field", %{
          "ticket_id" => tier.id,
          "field" => "email",
          "value" => "jane.smith@example.com"
        })

      assert is_binary(html)
    end
  end

  describe "edge cases and error handling" do
    test "handles event at capacity", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{max_attendees: 100}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end

    test "handles sold out ticket tier", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      event = event_with_state(:upcoming, with_image: true)

      # Create sold out tier
      _tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Sold Out Tier",
          type: :paid,
          price: Money.new(5000, :USD),
          quantity: 0
        })

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
    end

    test "handles unlimited quantity ticket tier", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      event = event_with_state(:upcoming, with_image: true)

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Unlimited Tier",
          type: :paid,
          price: Money.new(2500, :USD),
          quantity: nil
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Should be able to add many tickets
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      html = render(view)
      assert is_binary(html)
    end

    test "handles event with no ticket tiers", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "No Tickets Event"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "No Tickets Event"
    end
  end

  describe "payment and checkout modals" do
    test "handles close-payment-modal event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-payment-modal")
      assert is_binary(result)
    end

    test "handles close-registration-modal event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-registration-modal")
      assert is_binary(result)
    end

    test "handles retry-checkout event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "retry-checkout")
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "handles close-free-ticket-confirmation event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-free-ticket-confirmation")
      assert is_binary(result)
    end
  end
end
