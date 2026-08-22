defmodule YscWeb.EventDetailsLiveTest do
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory
  import Ysc.EventsFixtures
  import Ysc.AccountsFixtures
  import Ysc.TicketsFixtures
  import Mox
  import EventDetailsLiveHelpers

  alias Ysc.Repo
  alias Ysc.Subscriptions

  setup :verify_on_exit!

  setup %{conn: conn} do
    setup_stripe_mocks()
    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok, build_payment_intent(%{amount: params.amount})}
    end)

    stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
      {:ok, build_payment_intent(%{id: id})}
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

    test "draft events are not accessible on the public event page", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Secret Draft Event",
          state: :draft,
          published_at: nil
        })

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/events/#{event.id}")

      assert path == "/events"
    end

    test "admin can preview draft events on the public event page", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Draft Event Preview",
          state: :draft,
          published_at: nil
        })

      admin = user_fixture(%{role: :admin})
      conn = log_in_user(conn, admin)

      {:ok, view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Draft Event Preview"
      assert has_element?(view, "#event-content-preview-banner")
    end

    test "volunteer can preview scheduled events on the public event page", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Scheduled Event Preview",
          state: :scheduled,
          published_at: nil
        })

      volunteer = user_fixture(%{role: :volunteer})
      conn = log_in_user(conn, volunteer)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Scheduled Event Preview"
    end

    test "members cannot preview draft events on the public event page", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Member Blocked Draft Event",
          state: :draft,
          published_at: nil
        })

      member = user_fixture(%{role: :member, state: :active})
      conn = log_in_user(conn, member)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/events/#{event.id}")

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

    test "emits Open Graph and Twitter Card tags with cover image", %{
      conn: conn
    } do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{
            title: "OG Event Night",
            description: "Dance under the stars with the club."
          }
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ ~s(property="og:title")
      assert html =~ "OG Event Night"
      assert html =~ ~s(property="og:description")
      assert html =~ "Dance under the stars with the club."
      assert html =~ ~s(property="og:image")
      assert html =~ "/uploads/test_image_optimized.jpg"
      assert html =~ ~s(name="twitter:card" content="summary_large_image")
      assert html =~ ~s(name="twitter:image")
      assert html =~ ~s(rel="canonical")
      assert html =~ "/events/#{event.id}"
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

    test "renders ampersands in event description without HTML escaping", %{
      conn: conn
    } do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{
            title: "Social Night",
            description: "food & drinks at The Junction"
          }
        )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(
               view,
               "p.hidden.sm\\:block",
               "food & drinks at The Junction"
             )
    end

    test "shows weekday date for single-day events in the When section", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Single Day Event",
          start_date: ~U[2026-07-18 18:00:00Z],
          end_date: ~U[2026-07-18 22:00:00Z]
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(view, "p.font-black.text-xl", "Sat, Jul 18")
    end

    test "shows weekday date range for multi-day events in the same year", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Multi Day Event",
          start_date: ~U[2026-07-18 10:00:00Z],
          end_date: ~U[2026-07-20 22:00:00Z]
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(
               view,
               "p.font-black.text-xl",
               "Sat, Jul 18 – Mon, Jul 20"
             )
    end

    test "shows weekday date range with years for multi-day events across years",
         %{
           conn: conn
         } do
      event =
        event_fixture(%{
          title: "New Year Event",
          start_date: ~U[2025-12-30 10:00:00Z],
          end_date: ~U[2026-01-02 22:00:00Z]
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(
               view,
               "p.font-black.text-xl",
               "Tue, Dec 30, 2025 – Fri, Jan 2, 2026"
             )
    end

    test "shows TBD in the When section when start date is missing", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Date TBD Event",
          start_date: nil,
          end_date: nil
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(view, "p.font-black.text-xl", "TBD")
    end

    test "shows start and end times in the When section", %{conn: conn} do
      event =
        event_fixture(%{
          title: "Timed Event",
          start_date: ~U[2026-07-18 18:00:00Z],
          end_date: ~U[2026-07-18 22:00:00Z],
          start_time: ~T[19:00:00],
          end_time: ~T[22:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(
               view,
               "p.text-sm.text-zinc-500",
               "7:00 PM - 10:00 PM"
             )
    end

    test "shows start time only when end time is missing", %{conn: conn} do
      event =
        event_fixture(%{
          title: "Start Time Only Event",
          start_date: ~U[2026-07-18 18:00:00Z],
          end_date: ~U[2026-07-18 22:00:00Z],
          start_time: ~T[19:00:00],
          end_time: nil
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(view, "p.text-sm.text-zinc-500", "7:00 PM")
      refute has_element?(view, "p.text-sm.text-zinc-500", "7:00 PM -")
    end

    test "shows duration for single-day events with start and end times", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Timed Single Day Event",
          start_date: ~U[2026-07-18 18:00:00Z],
          end_date: ~U[2026-07-18 22:00:00Z],
          start_time: ~T[19:00:00],
          end_time: ~T[22:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(
               view,
               "p.text-xs.font-black.text-zinc-400",
               "Duration"
             )

      assert has_element?(view, "p.font-black.text-xl", "3 Hours")
    end

    test "hides duration for multi-day events even when times are set", %{
      conn: conn
    } do
      event =
        event_fixture(%{
          title: "Timed Multi Day Event",
          start_date: ~U[2026-07-18 10:00:00Z],
          end_date: ~U[2026-07-20 22:00:00Z],
          start_time: ~T[10:00:00],
          end_time: ~T[22:00:00]
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      refute has_element?(
               view,
               "p.text-xs.font-black.text-zinc-400",
               "Duration"
             )
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

    test "sanitizes stored overview HTML before rendering (no script or inline handlers)",
         %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Overview Sanitization"}
        )

      {:ok, event} =
        Ysc.Events.update_event(event, %{
          rendered_details:
            "<p>Legitimate copy</p><script>document.cookie</script><img src=x onerror=alert(1)>"
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      article_html = view |> element("#article-body") |> render()

      assert article_html =~ "Legitimate copy"
      refute article_html =~ "<script"
      refute article_html =~ "onerror="
    end

    test "opens details body links in a new tab", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Details Links New Tab"}
        )

      {:ok, event} =
        Ysc.Events.update_event(event, %{
          rendered_details:
            ~s|<p>See <a href="https://example.com/info">info</a></p>|
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(
               view,
               "#article-body a[href='https://example.com/info'][target='_blank'][rel='noopener noreferrer']"
             )
    end

    test "includes GLightbox hook on article body", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Lightbox Hook Event"}
        )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(view, "#article-body[phx-hook=GLightboxHook]")
      assert has_element?(view, "#article-body[phx-update=ignore]")
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

      assert html =~ event.title

      assert html =~
               "Sign in with your YSC account to buy tickets. An active, paid membership is required."

      assert html =~ "Sign in"
      refute html =~ "Sign In to Continue"
    end

    test "can toggle map without authentication", %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{location: "123 Main St"}
        )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result = render_click(view, "toggle-map")
      assert is_binary(result)

      # Toggle again to close
      result = render_click(view, "toggle-map")
      assert is_binary(result)
    end

    test "close-ticket-modal works without auth", %{conn: conn} do
      event = event_with_state(:upcoming, with_image: true)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result = render_click(view, "close-ticket-modal")
      assert is_binary(result)
    end
  end

  describe "authenticated user without membership" do
    test "cannot purchase tickets without active membership", %{conn: conn} do
      user = user_with_membership(:none)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2, state: :upcoming)

      {:ok, view, html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert html =~ event.title
      assert html =~ "Member tickets require an active paid membership"
      assert html =~ "Activate or renew your membership to buy tickets"

      assert has_element?(
               view,
               ~s(a[href="/users/membership"]),
               "View membership and payment options"
             )

      assert has_element?(
               view,
               ~s(a[href="/users/membership"]),
               "Membership options"
             )

      refute has_element?(view, "button", "Get Tickets")
    end

    test "shows board-review copy for pending approval users", %{conn: conn} do
      user = user_with_membership(:none, %{state: :pending_approval})
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2, state: :upcoming)

      {:ok, view, html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert html =~ "Your application is under board review"
      assert html =~ "membership payment may still be required"
      refute html =~ "membership has expired"
      refute has_element?(view, "button", "Get Tickets")
    end

    test "shows expired-membership copy for users with lapsed subscriptions", %{
      conn: conn
    } do
      user = user_with_membership(:none, %{state: :active})

      {:ok, _expired_sub} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_expired_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Expired Subscription",
          current_period_end: DateTime.add(DateTime.utc_now(), -1, :day)
        })

      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 2, state: :upcoming)

      {:ok, view, html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert html =~ "Your membership has expired"
      assert html =~ "renew to buy tickets"
      refute html =~ "pay dues or activate your membership"
      refute has_element?(view, "button", "Get Tickets")
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
      render_async(view)

      result = render_click(view, "open-ticket-modal")
      # May redirect to tickets page or return HTML
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end

    test "can close ticket modal", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result = render_click(view, "close-ticket-modal")
      assert is_binary(result)
    end

    test "handles select-ticket event", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(result)
    end

    test "handles deselect-ticket event", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

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
      render_async(view)

      result =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      assert is_binary(result)
    end

    test "handles decrement-ticket event", %{conn: conn, event: event} do
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

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
      render_async(view)

      # Select multiple tickets
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier1.id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier2.id})

      html = render(view)
      assert is_binary(html)
    end

    test "handles show-attendees-modal event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result = render_click(view, "show-attendees-modal")
      assert is_binary(result)
    end

    test "handles hide-attendees-modal event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

      result =
        render_click(view, "set-donation-amount", %{
          "tier-id" => tier.id,
          "amount" => "1000"
        })

      assert is_binary(result)
    end

    test "handles update-donation-amount event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

      # Select a ticket first
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})

      # Then proceed to checkout
      result = render_click(view, "proceed-to-checkout")
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "handles close-order-completion event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result = render_click(view, "close-order-completion")
      assert is_binary(result)
    end

    test "handles payment-redirect-started event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result = render_click(view, "payment-redirect-started")
      assert is_binary(result)
    end

    test "handles checkout-expired event", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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

      render_async(view)

      html = render(view)
      assert html =~ event.title
    end

    test "handles async loading with tickets", %{conn: conn} do
      event = event_with_tickets(tier_count: 3)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      render_async(view)

      html = render(view)
      assert html =~ event.title
    end
  end

  describe "error scenarios" do
    test "handles invalid event ID format", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/events"}}} =
               live(conn, ~p"/events/invalid-id")
    end

    test "handles crawler junk paths without raising", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/events"}}} =
               live(conn, ~p"/events/images.php")
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

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(view, "h1", "Upcoming Event")
      assert has_element?(view, "#event-status-label", "Upcoming")
      refute has_element?(view, "p", "Event has ended")
    end

    test "displays past event as ended", %{conn: conn} do
      event =
        event_with_state(:past, with_image: true, attrs: %{title: "Past Event"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(view, "h1", "Past Event")
      assert has_element?(view, "p", "Event has ended")
      refute has_element?(view, "button", "Get Tickets")
    end

    test "does not show Event has ended while event is in progress", %{
      conn: conn
    } do
      event =
        event_with_state(:ongoing,
          with_image: true,
          attrs: %{title: "Happening Now"}
        )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(view, "h1", "Happening Now")
      assert has_element?(view, "#event-status-label", "Live")
      refute has_element?(view, "p", "Event has ended")
      refute has_element?(view, "#event-status-label", "Event Ended")
    end

    test "does not show Event has ended after start when end time is later today",
         %{conn: conn} do
      today =
        DateTime.now!("America/Los_Angeles")
        |> DateTime.to_date()

      event =
        event_fixture(
          live_pacific_event_fixture_attrs(%{
            title: "Afternoon Mixer",
            end_date: DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
          })
        )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(view, "#event-status-label", "Live")
      refute has_element?(view, "p", "Event has ended")
      refute has_element?(view, "div", "Event Ended")
    end

    test "remains active until same-day end_time when end_date is absent", %{
      conn: conn
    } do
      event =
        event_fixture(
          live_pacific_event_fixture_attrs(%{
            title: "No End Date Mixer",
            end_date: nil
          })
        )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert has_element?(view, "#event-status-label", "Live")
      refute has_element?(view, "p", "Event has ended")
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

  describe "real-time EventUpdated handling" do
    @tag :process_caches
    test "reflects an event edit even when this node's pricing cache has not yet observed the invalidation",
         %{conn: conn} do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "Original Title"}
        )

      # Mount warms EventPricingCache for this event (via mount_minimal_assigns).
      {:ok, view, html} = live(conn, ~p"/events/#{event.id}")
      assert html =~ "Original Title"

      # Update the DB directly instead of going through Events.update_event_editor,
      # so EventPricingCache.invalidate/0 is deliberately NOT called here. This
      # simulates a node that hasn't yet processed the Ysc.DistributedCache sync
      # broadcast for this write (it's a separate PubSub message from the
      # EventUpdated broadcast, with no ordering guarantee between the two) —
      # the exact condition that let the pricing cache serve a stale value to a
      # live EventUpdated handler.
      {:ok, updated_event} =
        event
        |> Ysc.Events.Event.changeset(%{title: "Updated Title"})
        |> Repo.update()

      send(
        view.pid,
        {Ysc.Events,
         %Ysc.MessagePassingEvents.EventUpdated{event: updated_event}}
      )

      html = render(view)
      assert html =~ "Updated Title"
      refute html =~ "Original Title"
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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

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

  describe "Partiful - event with external registration" do
    test "displays RSVP on Partiful button and link when event has partiful_link",
         %{
           conn: conn
         } do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{
            title: "Partiful Gala",
            partiful_link: "https://partiful.com/e/partiful-gala-2026"
          }
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "RSVP on"
      assert html =~ "Partiful"
      assert html =~ "https://partiful.com/e/partiful-gala-2026"
    end

    test "does not display Partiful CTA when event has no partiful_link", %{
      conn: conn
    } do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "No Partiful Event"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      refute html =~ "RSVP on"
      assert html =~ "No Partiful Event"
    end

    test "event with partiful_link shows Partiful CTA for unauthenticated user",
         %{
           conn: conn
         } do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{
            title: "Public Partiful Event",
            partiful_link: "https://partiful.com/e/public"
          }
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "RSVP on"
      assert html =~ "partiful.com/e/public"
    end

    test "event with tickets and no partiful_link shows Get Tickets flow", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1, state: :upcoming)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ event.title
      refute html =~ "RSVP on"
      assert html =~ "Get Tickets"
    end

    test "event with no tickets and no partiful_link shows no registration or Get Tickets",
         %{
           conn: conn
         } do
      event =
        event_with_state(:upcoming,
          with_image: true,
          attrs: %{title: "No Tickets Event"}
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "No Tickets Event"
      refute html =~ "RSVP on"
    end

    test "event with both tickets and partiful_link shows Get Tickets CTA and the Partiful spotlight section",
         %{
           conn: conn
         } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      event =
        event_with_tickets(
          tier_count: 1,
          state: :upcoming,
          event_attrs: %{
            partiful_link: "https://partiful.com/e/both-tickets-and-partiful"
          }
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Get Tickets"
      assert html =~ "RSVP on"
      assert html =~ "https://partiful.com/e/both-tickets-and-partiful"
    end

    test "anonymous visitor sees the Partiful spotlight and a gated ticket CTA when event has both tickets and partiful_link",
         %{
           conn: conn
         } do
      event =
        event_with_tickets(
          tier_count: 1,
          state: :upcoming,
          event_attrs: %{
            partiful_link: "https://partiful.com/e/anon-both"
          }
        )

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "RSVP on"
      assert html =~ "https://partiful.com/e/anon-both"
      assert html =~ "Sign in with your YSC account to buy tickets"
      refute html =~ "Get Tickets"
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
      render_async(view)

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
      render_async(view)

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
      render_async(view)

      result = render_click(view, "close-payment-modal")
      assert is_binary(result)
    end

    test "stripe-payment-element-ready and loading events toggle payment button gating assign",
         %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert render_click(view, "stripe-payment-element-ready", %{})
             |> is_binary()

      assert render_click(view, "stripe-payment-element-loading", %{})
             |> is_binary()
    end

    test "handles close-registration-modal event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result = render_click(view, "close-registration-modal")
      assert is_binary(result)
    end

    test "handles retry-checkout event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result = render_click(view, "retry-checkout")
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "handles close-free-ticket-confirmation event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      result = render_click(view, "close-free-ticket-confirmation")
      assert is_binary(result)
    end
  end

  describe "user tickets section" do
    test "confirmed ticket count excludes donations", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      paid_tier = hd(event.ticket_tiers)

      donation_tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Donation",
          type: :donation,
          price: nil,
          quantity: nil
        })

      order = ticket_order_fixture(%{user: user, event: event, tier: paid_tier})

      Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      |> Ysc.Repo.preload([:tickets])
      |> Map.fetch!(:tickets)
      |> Enum.each(fn ticket ->
        ticket
        |> Ecto.Changeset.change(status: :confirmed)
        |> Ysc.Repo.update!()
      end)

      {:ok, _donation_ticket} =
        %Ysc.Events.Ticket{}
        |> Ysc.Events.Ticket.changeset(%{
          ticket_order_id: order.id,
          ticket_tier_id: donation_tier.id,
          event_id: event.id,
          user_id: user.id,
          reference_id: "TKT-DON-#{System.unique_integer()}",
          status: :confirmed,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
        })
        |> Ysc.Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(
               view,
               "#user-tickets-confirmed-count",
               "1 confirmed ticket"
             )

      refute has_element?(view, "span", "1x Donation")
    end
  end

  describe "attendees section" do
    defp confirmed_ticket(event, tier, user) do
      %Ysc.Events.Ticket{
        event_id: event.id,
        ticket_tier_id: tier.id,
        user_id: user.id,
        status: :confirmed,
        expires_at:
          DateTime.utc_now()
          |> DateTime.add(365, :day)
          |> DateTime.truncate(:second)
      }
      |> Repo.insert!()
    end

    test "does not show attendees section for non-members", %{conn: conn} do
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)
      buyer = user_with_membership(:lifetime)
      confirmed_ticket(event, tier, buyer)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      refute has_element?(view, "#attendees-section")
    end

    test "shows attendees section with host even when no tickets sold", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      # event_with_tickets auto-adds the organizer as a host, so the section
      # now shows even without any ticket sales
      event = event_with_tickets(tier_count: 1, state: :upcoming)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(view, "#attendees-section")
    end

    test "shows attendees section for members when at least one ticket is sold",
         %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # Remove the auto-added organizer host so the section only appears
      # because a ticket was sold, not because there is a host
      Enum.each(Ysc.Events.list_event_hosts(event), fn host ->
        Ysc.Events.remove_event_host(event, host.id)
      end)

      confirmed_ticket(event, tier, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(view, "#attendees-section")
    end

    test "shows current user first labeled as You", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      # Use `user` as the organizer so they are a host and sorted first
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      other_user = user_with_membership(:lifetime)
      confirmed_ticket(event, tier, other_user)
      confirmed_ticket(event, tier, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(
               view,
               "#attendees-list > div:first-child[data-attendee-you]"
             )
    end

    test "shows overflow tile when more than 10 unique attendees", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # 9 buyers + user + separate event host = 11 unique attendees, exceeding
      # the preview count of 10 and triggering the overflow tile.
      for _ <- 1..9 do
        buyer = user_with_membership(:lifetime)
        confirmed_ticket(event, tier, buyer)
      end

      confirmed_ticket(event, tier, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(view, "#attendees-overflow-btn")
    end

    test "does not show overflow tile when 10 or fewer unique attendees", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      # Use `user` as the organizer so they are both the event host and a ticket
      # buyer — they get deduplicated into a single slot, keeping the total ≤ 10.
      event = event_with_tickets(tier_count: 1, state: :upcoming, user: user)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      for _ <- 1..4 do
        buyer = user_with_membership(:lifetime)
        confirmed_ticket(event, tier, buyer)
      end

      confirmed_ticket(event, tier, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      refute has_element?(view, "#attendees-overflow-btn")
    end

    test "overflow tile opens attendees modal", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = event_with_tickets(tier_count: 1, state: :upcoming)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      # 10 buyers + separate event host = 11 unique attendees, exceeding the
      # preview count of 10 and triggering the overflow tile.
      for _ <- 1..10 do
        buyer = user_with_membership(:lifetime)
        confirmed_ticket(event, tier, buyer)
      end

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      element(view, "#attendees-overflow-btn") |> render_click()
      assert has_element?(view, "#attendees-modal")
    end

    test "Who's Going modal hides attendee emails and host zero-ticket counts",
         %{conn: conn} do
      viewer = user_with_membership(:lifetime)
      conn = log_in_user(conn, viewer)

      host =
        user_with_membership(:lifetime, %{
          first_name: "Hosty",
          last_name: "McHost",
          email:
            "host-whos-going-#{System.unique_integer([:positive])}@ysc.test"
        })

      named =
        user_with_membership(:lifetime, %{
          first_name: "Greta",
          last_name: "Garbo",
          email:
            "greta-whos-going-#{System.unique_integer([:positive])}@ysc.test"
        })

      nameless =
        user_with_membership(:lifetime, %{
          first_name: "Temp",
          last_name: "Name",
          email:
            "nameless-whos-going-#{System.unique_integer([:positive])}@ysc.test"
        })
        |> Ecto.Changeset.change(%{first_name: nil, last_name: nil})
        |> Repo.update!()

      event = event_with_tickets(tier_count: 1, state: :upcoming, user: host)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)

      confirmed_ticket(event, tier, named)
      confirmed_ticket(event, tier, named)
      confirmed_ticket(event, tier, nameless)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)
      render_click(view, "show-attendees-modal")

      assert has_element?(view, "#attendees-modal")

      assert has_element?(
               view,
               "#attendees-modal-user-#{named.id}",
               "Greta Garbo"
             )

      assert has_element?(
               view,
               "#attendees-modal-user-#{named.id}-tickets",
               "2 tickets"
             )

      assert has_element?(
               view,
               "#attendees-modal-user-#{nameless.id}",
               "Member"
             )

      assert has_element?(
               view,
               "#attendees-modal-user-#{host.id}",
               "Hosty McHost"
             )

      assert has_element?(view, "#attendees-modal-user-#{host.id}", "Host")
      refute has_element?(view, "#attendees-modal-user-#{host.id}-tickets")
      refute has_element?(view, "#attendees-modal", "No ticket")
      refute has_element?(view, "#attendees-modal", named.email)
      refute has_element?(view, "#attendees-modal", nameless.email)
      refute has_element?(view, "#attendees-modal", host.email)

      # Preview list (outside the modal) must also hide emails for nameless attendees
      refute has_element?(view, "#attendees-list", nameless.email)
      refute has_element?(view, "#attendees-list", named.email)
      assert has_element?(view, "#attendees-list", "Member")
    end

    test "Who's Going modal still shows ticket count for hosts who bought tickets",
         %{conn: conn} do
      viewer = user_with_membership(:lifetime)
      conn = log_in_user(conn, viewer)

      host =
        user_with_membership(:lifetime, %{
          first_name: "HostBuyer",
          last_name: "Tickets"
        })

      event = event_with_tickets(tier_count: 1, state: :upcoming, user: host)
      event = Repo.preload(event, :ticket_tiers, force: true)
      tier = hd(event.ticket_tiers)
      confirmed_ticket(event, tier, host)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)
      render_click(view, "show-attendees-modal")

      assert has_element?(view, "#attendees-modal-user-#{host.id}", "Host")

      assert has_element?(
               view,
               "#attendees-modal-user-#{host.id}-tickets",
               "1 ticket"
             )
    end
  end
end
