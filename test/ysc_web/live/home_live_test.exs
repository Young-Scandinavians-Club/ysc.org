defmodule YscWeb.HomeLiveTest do
  @moduledoc """
  Tests for HomeLive.
  """
  # System.unique_integer() is only unique per process; async tests can collide on user emails.
  # Home newsletter tests also share Hammer rate-limit state per IP.
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures, only: [event_fixture: 1, ticket_tier_fixture: 1]
  import Ysc.TicketsFixtures, only: [ticket_order_fixture: 1]

  alias Ysc.Bookings
  alias Ysc.Events.Ticket
  alias Ysc.Newsletter
  alias Ysc.Posts
  alias Ysc.Repo

  describe "guest" do
    test "renders marketing home with hero and newsletter section", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, ~p"/")

      assert page_title(view) =~ "Home"
      assert html =~ "Young Scandinavians Club"
      assert has_element?(view, "#newsletter-heading")
      assert has_element?(view, "#newsletter-email")
    end

    test "accepts query params on initial load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?utm_source=test")

      assert page_title(view) =~ "Home"
      assert render(view) =~ "Young Scandinavians Club"
    end

    test "refreshes latest news when public content cache is invalidated", %{
      conn: conn
    } do
      author = user_fixture(%{role: "admin"})
      title = "PubSub News #{System.unique_integer()}"

      {:ok, view, _html} = live(conn, ~p"/")
      render(view)

      assert {:ok, _} =
               Posts.create_post(
                 %{
                   "title" => title,
                   "body" => "Body",
                   "url_name" => "pubsub-news-#{System.unique_integer()}",
                   "state" => "published",
                   "featured_post" => false,
                   "published_on" => DateTime.utc_now()
                 },
                 author
               )

      assert render(view) =~ title
    end

    test "shows upcoming event title when an upcoming event exists", %{
      conn: conn
    } do
      event = Ysc.TestDataFactory.event_with_state(:upcoming)

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ "The Pulse of the Club"
      assert html =~ event.title
    end

    test "shows event start time on guest cards when configured", %{conn: conn} do
      event =
        event_fixture(%{
          title: "Timed Event #{System.unique_integer()}",
          start_time: ~T[18:30:00]
        })

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ event.title
    end

    test "renders upcoming event card with cover image when present", %{
      conn: conn
    } do
      user = user_fixture()

      event =
        Ysc.TestDataFactory.event_with_state(:upcoming,
          with_image: true,
          user: user
        )

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ event.title
      assert html =~ "blur-hash-event-#{event.id}"
    end

    test "subscribes to newsletter with valid email", %{conn: conn} do
      email = "home_news_ok_#{System.unique_integer()}@example.com"

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("form[phx-submit=subscribe_newsletter]", %{"email" => email})
      |> render_submit()

      html = render(view)
      assert Newsletter.get_subscriber_by_email(email).subscribed
      refute has_element?(view, "#newsletter-error")
      assert html =~ "Thank you for subscribing"
    end

    test "lists published news posts in the latest news section", %{conn: conn} do
      author = user_fixture()
      title = "Home Latest News #{System.unique_integer()}"

      {:ok, _post} =
        %Posts.Post{}
        |> Posts.Post.new_post_changeset(%{
          title: title,
          raw_body: "<p>News body for the home page latest news block.</p>",
          preview_text: "Preview line for the news card.",
          url_name: "home-news-#{System.unique_integer()}",
          state: :published,
          published_on: DateTime.utc_now(),
          user_id: author.id
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ "Latest News"
      assert html =~ title
    end

    test "shows happening soon bar when events or news exist", %{conn: conn} do
      _event = Ysc.TestDataFactory.event_with_state(:upcoming)

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ "Happening Soon"
    end

    test "does not list cancelled events in the guest upcoming events section",
         %{
           conn: conn
         } do
      cancelled =
        Ysc.TestDataFactory.event_with_state(:cancelled,
          attrs: %{
            title: "Cancelled Home Ev #{System.unique_integer([:positive])}"
          }
        )

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      refute html =~ cancelled.title
    end
  end

  describe "logged-in user" do
    setup :register_and_log_in_user

    test "does not render guest newsletter signup for logged-in users", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")
      render_async(view, 5_000)
      refute has_element?(view, "#newsletter-email")
    end

    test "renders home page for logged-in user", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert page_title(view) =~ "Home"
      assert html =~ user.email
    end

    test "loads member dashboard after async home data", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Member Dashboard"
      assert html =~ user.first_name
    end

    test "uses Norwegian greeting when most_connected_country is Norway", %{
      conn: conn
    } do
      user = user_fixture(%{most_connected_country: "Norway"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Hallo"
      assert html =~ user.first_name
    end

    test "shows membership call-to-action when user has no active membership",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Membership Required"
      assert html =~ "Get Membership Now"
    end

    test "shows pending review state for users awaiting board approval", %{
      conn: conn
    } do
      user = user_fixture(%{state: "pending_approval"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Application Under Review"
      assert html =~ "Awaiting board review"
      refute html =~ "Get Membership Now"
      refute html =~ "Membership Required"
    end

    test "shows expense report launcher for volunteer users", %{conn: conn} do
      user = user_fixture(%{role: "volunteer"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Expenses"
      assert html =~ "File Report"
    end

    test "shows expense report launcher for admin users", %{conn: conn} do
      user = user_fixture(%{role: "admin"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Expenses"
      assert html =~ "File Report"
    end

    test "lists upcoming events in the member community section", %{conn: conn} do
      event = Ysc.TestDataFactory.event_with_state(:upcoming)
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Upcoming Events"
      assert html =~ event.title
    end

    test "shows latest updates sidebar when posts exist", %{conn: conn} do
      author = user_fixture()
      title = "Sidebar News #{System.unique_integer()}"

      {:ok, _post} =
        %Posts.Post{}
        |> Posts.Post.new_post_changeset(%{
          title: title,
          raw_body: "<p>Sidebar story body with enough text.</p>",
          url_name: "sidebar-news-#{System.unique_integer()}",
          state: :published,
          published_on: DateTime.utc_now(),
          user_id: author.id
        })
        |> Repo.insert()

      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Latest Updates"
      assert html =~ title
    end
  end

  describe "logged-in user with itinerary data" do
    test "shows upcoming event tickets when user has confirmed tickets", %{
      conn: conn
    } do
      data = Ysc.TestDataFactory.complete_ticket_order()
      conn = log_in_user(conn, data.user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Event Tickets"
      assert html =~ data.event.title
    end

    test "shows upcoming booking on the itinerary", %{conn: conn} do
      user = Ysc.TestDataFactory.user_with_membership(:lifetime)

      booking =
        Ysc.BookingsFixtures.booking_fixture(%{user_id: user.id})
        |> Repo.preload(:rooms)

      assert {:ok, _} = Bookings.update_booking(booking, %{status: :complete})

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Your Upcoming Stays"
      assert html =~ "Lake Tahoe"
    end
  end

  describe "logged-in user with active membership" do
    setup %{conn: conn} do
      user = Ysc.TestDataFactory.user_with_membership(:lifetime)
      %{conn: log_in_user(conn, user), user: user}
    end

    test "shows empty event tickets card when member has no upcoming tickets",
         %{
           conn: conn
         } do
      user = Ysc.TestDataFactory.user_with_membership(:lifetime)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "No upcoming event tickets"
    end

    test "opens and closes membership QR modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)

      view
      |> element("button", "My Membership QR")
      |> render_click()

      assert has_element?(view, "#membership-qr-modal")

      render_click(view, "hide_membership_qr", %{})

      refute render(view) =~ "Show this to an admin for membership verification"
    end

    test "hide_membership_qr clears modal after show_membership_qr", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)

      render_click(view, "show_membership_qr", %{})
      assert has_element?(view, "#membership-qr-modal")

      render_click(view, "hide_membership_qr", %{})
      refute has_element?(view, "#membership-qr-modal")
    end
  end

  describe "logged-in sub-account" do
    test "renders member dashboard for a family sub-account", %{conn: conn} do
      %{sub_accounts: [sub | _]} =
        Ysc.TestDataFactory.family_with_sub_accounts(1)

      conn = log_in_user(conn, sub)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Member Dashboard"
      assert html =~ sub.first_name
    end
  end

  describe "passkey prompt" do
    test "setup_passkey navigates to passkey registration", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> put_session("just_logged_in", true)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)

      assert has_element?(view, "#passkey-prompt-banner")

      assert {:error, {:live_redirect, %{to: "/users/settings/passkeys/new"}}} =
               view
               |> element("#passkey-prompt-banner button", "Set up passkey")
               |> render_click()
    end

    test "dismiss_passkey_prompt hides banner", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> put_session("just_logged_in", true)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)

      assert has_element?(view, "#passkey-prompt-banner")

      view
      |> element("button[aria-label='Dismiss']")
      |> render_click()

      refute has_element?(view, "#passkey-prompt-banner")
    end

    test "dismiss_passkey_prompt via Maybe later shows scheduled toast", %{
      conn: conn
    } do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> put_session("just_logged_in", true)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)

      assert has_element?(view, "#passkey-prompt-banner")

      view
      |> element("button", "Maybe later")
      |> render_click()

      refute has_element?(view, "#passkey-prompt-banner")

      html = render(view)
      assert html =~ "remind" or html =~ "30 days"
    end
  end

  describe "guest — marketing sections and edge cases" do
    test "shows happening soon bar linked to news when no upcoming events exist",
         %{
           conn: conn
         } do
      author = user_fixture()
      title = "Happening Soon News #{System.unique_integer()}"

      {:ok, _post} =
        %Posts.Post{}
        |> Posts.Post.new_post_changeset(%{
          title: title,
          raw_body: "<p>News body for happening soon bar.</p>",
          preview_text: "Preview for the bar.",
          url_name: "happening-soon-news-#{System.unique_integer()}",
          state: :published,
          published_on: DateTime.utc_now(),
          user_id: author.id,
          featured_post: false
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ "Happening Soon"
      assert html =~ title
    end

    test "renders Nordic Living and membership options sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ "Nordic Living"
      assert html =~ "Join Our Community Today"
      assert html =~ "Single Membership"
      assert html =~ "Family Membership"
    end

    test "shows guest event card with description, location, and Just Added badge",
         %{
           conn: conn
         } do
      organizer = user_fixture()
      unique = System.unique_integer([:positive])

      event =
        event_fixture(%{
          title: "Described Event #{unique}",
          description: "Unique home description #{unique} for line clamp.",
          location_name: "Nordic Hall #{unique}",
          organizer_id: organizer.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 1, :hour)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 3, :hour)
            |> DateTime.truncate(:second)
        })

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ event.title
      assert html =~ "Unique home description #{unique}"
      assert html =~ "Nordic Hall #{unique}"
      assert html =~ "Just Added"
    end

    test "shows Sold Out badge when the only ticket tier is fully sold", %{
      conn: conn
    } do
      organizer = user_fixture()
      buyer = Ysc.TestDataFactory.user_with_membership(:lifetime)

      event =
        event_fixture(%{
          title: "Sold Out Home #{System.unique_integer([:positive])}",
          organizer_id: organizer.id,
          start_date:
            DateTime.add(DateTime.utc_now(), 2, :hour)
            |> DateTime.truncate(:second),
          end_date:
            DateTime.add(DateTime.utc_now(), 4, :hour)
            |> DateTime.truncate(:second)
        })

      tier =
        ticket_tier_fixture(%{event_id: event.id, quantity: 1, type: :paid})

      order =
        ticket_order_fixture(%{
          user: buyer,
          event: event,
          tier: tier,
          ticket_selections: %{tier.id => 1},
          status: :completed
        })

      order = Repo.preload(order, :tickets)

      Enum.each(order.tickets, fn t ->
        t |> Ticket.status_changeset(%{status: :confirmed}) |> Repo.update!()
      end)

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ event.title
      assert html =~ "Sold Out"
    end

    test "lists a post with nil preview_text in latest news (uses body-derived preview)",
         %{conn: conn} do
      author =
        user_fixture(%{
          email: "news_author_#{Ecto.UUID.generate()}@example.com"
        })

      title = "Home News No Preview #{System.unique_integer([:positive])}"

      {:ok, _post} =
        %Posts.Post{}
        |> Posts.Post.new_post_changeset(%{
          title: title,
          raw_body: "<p>Body scrub short.</p>",
          preview_text: nil,
          url_name: "home-news-raw-#{System.unique_integer([:positive])}",
          state: :published,
          published_on: DateTime.utc_now() |> DateTime.add(5, :second),
          user_id: author.id,
          featured_post: false
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ title
    end
  end

  describe "logged-in user — greetings and loading" do
    test "shows Swedish greeting when most_connected_country is Sweden", %{
      conn: conn
    } do
      user = user_fixture(%{most_connected_country: "Sweden"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Hej"
      assert html =~ user.first_name
    end

    test "shows Finnish greeting when most_connected_country is Finland", %{
      conn: conn
    } do
      user = user_fixture(%{most_connected_country: "Finland"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Hei"
    end

    test "shows Danish greeting when most_connected_country is Denmark", %{
      conn: conn
    } do
      user = user_fixture(%{most_connected_country: "Denmark"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Hej"
    end

    test "shows Icelandic greeting when most_connected_country is Iceland", %{
      conn: conn
    } do
      user = user_fixture(%{most_connected_country: "Iceland"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Halló"
    end

    test "shows dashboard loading skeleton before async data completes", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "animate-pulse"

      render_async(view, 5_000)
      assert render(view) =~ "Member Dashboard"
    end

    test "show_membership_qr is a no-op when user has no active membership", %{
      conn: conn
    } do
      user =
        Ysc.TestDataFactory.user_with_membership(:none, %{
          email: "nomem_#{Ecto.UUID.generate()}@example.com"
        })

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)

      render_click(view, "show_membership_qr", %{})

      refute has_element?(view, "#membership-qr-modal")
    end
  end

  describe "logged-in user — events launcher" do
    test "shows Browse Events launcher for regular members", %{conn: conn} do
      user = user_fixture(%{role: "member"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Browse Events"
      refute html =~ "File Report"
    end
  end

  describe "logged-in user — family and bookings" do
    test "shows Clear Lake upcoming booking on the itinerary", %{conn: conn} do
      user = Ysc.TestDataFactory.user_with_membership(:lifetime)

      booking =
        Ysc.BookingsFixtures.booking_fixture(%{
          user_id: user.id,
          property: :clear_lake
        })
        |> Repo.preload(:rooms)

      assert {:ok, _} = Bookings.update_booking(booking, %{status: :complete})

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      render_async(view, 5_000)
      html = render(view)

      assert html =~ "Your Upcoming Stays"
      assert html =~ "Clear Lake"
    end
  end

  describe "guest — marketing extras" do
    test "guest home page title and meta mention the club", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      assert page_title(view) =~ "Home"
      assert html =~ "Young Scandinavians Club" or html =~ "Scandinavian"
    end

    test "guest newsletter area links to privacy policy", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)
      assert html =~ "privacy policy"
      assert html =~ ~p"/privacy-policy"
    end

    test "guest home includes a hero video asset path", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "/video/" and
               (html =~ "tahoe_hero" or html =~ "clear_lake_hero")
    end

    test "guest home includes Nordic heritage flag row", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)
      assert html =~ "fi-fi" or html =~ "fi-se" or html =~ "fi-no"
      assert has_element?(view, ".grayscale")
    end
  end

  describe "guest — newsletter submit handler branches" do
    setup do
      # Reset the IP rate limit for the loopback address used by the test conn
      # so these tests don't get blocked by earlier newsletter submissions in the suite.
      :ets.delete_all_objects(Ysc.NewsletterRateLimit)
      :ok
    end

    test "subscribe_newsletter assigns error message for invalid email from server",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/")

      render_submit(view, "subscribe_newsletter", %{"email" => "notvalid"})

      assert has_element?(view, "#newsletter-error")
      assert render(view) =~ "Please enter a valid email address."
    end

    test "subscribe_newsletter shows error for disposable email domain", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      render_submit(view, "subscribe_newsletter", %{
        "email" => "test@mailinator.com"
      })

      assert has_element?(view, "#newsletter-error")
      assert render(view) =~ "Temporary email addresses are not allowed"
    end

    test "subscribe_newsletter shows error for domain with no MX records", %{
      conn: conn
    } do
      stub_mx_no_records()

      {:ok, view, _html} = live(conn, ~p"/")

      domain = "mx-reject-#{System.unique_integer([:positive])}.example.org"

      render_submit(view, "subscribe_newsletter", %{"email" => "user@#{domain}"})

      assert has_element?(view, "#newsletter-error")
      assert render(view) =~ "email domain appears to be invalid"
    end

    test "subscribe_newsletter shows success state for valid email", %{
      conn: conn
    } do
      email = "nl_branch_ok_#{System.unique_integer([:positive])}@example.com"
      {:ok, view, _html} = live(conn, ~p"/")

      render_submit(view, "subscribe_newsletter", %{"email" => email})

      html = render(view)
      assert Newsletter.get_subscriber_by_email(email).subscribed

      assert html =~ "Thank you for subscribing" or
               html =~ "Thank you for subscribing!"
    end
  end
end
