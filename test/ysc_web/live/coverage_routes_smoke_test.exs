defmodule YscWeb.CoverageRoutesSmokeTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  import Mox

  alias Ysc.Media.Image
  alias Ysc.Repo

  alias Ysc.BookingsFixtures
  alias Ysc.EventsFixtures
  alias Ysc.Posts

  setup :verify_on_exit!

  describe "public routes (smoke)" do
    test "renders core public LiveViews without crashing", %{conn: conn} do
      admin_author = user_fixture(%{role: :admin})

      # Event templates assume events have a cover image.
      cover_image =
        %Image{
          user_id: admin_author.id,
          raw_image_path: "media/raw/smoke.jpg",
          optimized_image_path: "media/optimized/smoke.jpg",
          thumbnail_path: "media/thumb/smoke.jpg",
          processing_state: "completed",
          width: 1200,
          height: 800
        }
        |> Repo.insert!()

      event = EventsFixtures.event_fixture(%{image_id: cover_image.id})
      EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Smoke Post",
            "preview_text" => "Preview",
            "body" => "Body",
            "url_name" => "smoke-post",
            "state" => "published",
            # NewsLive formats this date; ensure it's valid.
            "published_on" => DateTime.utc_now()
          },
          admin_author
        )

      # Public pages / informational routes
      assert {:ok, _view, _html} = live(conn, ~p"/")
      assert {:ok, _view, _html} = live(conn, ~p"/events")
      assert {:ok, _view, _html} = live(conn, ~p"/events/#{event.id}")
      assert {:ok, _view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
      assert {:ok, _view, _html} = live(conn, ~p"/news")
      assert {:ok, _view, _html} = live(conn, ~p"/posts/#{post.id}")
      assert {:ok, _view, _html} = live(conn, ~p"/volunteer")
      assert {:ok, _view, _html} = live(conn, ~p"/report-conduct-violation")
      assert {:ok, _view, _html} = live(conn, ~p"/contact")

      # Booking marketing pages (no auth required)
      assert {:ok, _view, _html} = live(conn, ~p"/bookings/tahoe")

      # Note: /bookings/tahoe/staying-with is a native-only route (SwiftUI), skip in web test
      assert {:ok, _view, _html} = live(conn, ~p"/bookings/clear-lake")

      # Basic controllers (hit plug pipelines + controller code)
      assert %Plug.Conn{status: 200} = get(conn, ~p"/up")
      assert %Plug.Conn{status: 200} = get(conn, ~p"/up/dbs")
      assert %Plug.Conn{status: 200} = get(conn, ~p"/history")
      assert %Plug.Conn{status: 200} = get(conn, ~p"/board")
      assert %Plug.Conn{status: 200} = get(conn, ~p"/bylaws")
      assert %Plug.Conn{status: 200} = get(conn, ~p"/code-of-conduct")
      assert %Plug.Conn{status: 200} = get(conn, ~p"/privacy-policy")
      assert %Plug.Conn{status: 200} = get(conn, ~p"/terms-of-service")
    end
  end

  describe "authenticated routes (smoke)" do
    test "renders key authenticated LiveViews without crashing", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      booking =
        BookingsFixtures.booking_fixture(%{user_id: user.id, status: :hold})

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      stub(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_smoke_123",
           client_secret: "pi_smoke_123_secret",
           status: "requires_payment_method"
         }}
      end)

      # Most auth views should mount and render
      assert {:ok, _view, _html} = live(conn, ~p"/users/settings")
      assert {:ok, _view, _html} = live(conn, ~p"/users/settings/security")

      assert {:ok, _view, _html} =
               live(conn, ~p"/users/settings/phone-verification")

      assert {:ok, _view, _html} =
               live(conn, ~p"/users/settings/email-verification")

      assert {:ok, _view, _html} = live(conn, ~p"/users/settings/family")
      assert {:ok, _view, _html} = live(conn, ~p"/users/tickets")
      assert {:ok, _view, _html} = live(conn, ~p"/users/payments")
      assert {:ok, _view, _html} = live(conn, ~p"/users/membership")
      assert {:ok, _view, _html} = live(conn, ~p"/users/notifications")

      # Booking-related authenticated routes
      assert {:ok, _view, _html} = live(conn, ~p"/bookings/#{booking.id}")

      assert {:ok, _view, _html} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")

      assert {:ok, _view, _html} =
               live(conn, ~p"/bookings/#{booking.id}/receipt")

      # Expense reports (auth)
      assert {:ok, _view, _html} = live(conn, ~p"/expensereport")
      assert {:ok, _view, _html} = live(conn, ~p"/expensereports")
    end
  end

  describe "admin routes (smoke)" do
    test "renders key admin LiveViews without crashing", %{conn: conn} do
      admin = user_fixture(%{role: :admin})
      conn = log_in_user(conn, admin)

      # Admin landing pages
      assert {:ok, _view, _html} = live(conn, ~p"/admin")
      assert {:ok, _view, _html} = live(conn, ~p"/admin/bookings")
      assert {:ok, _view, _html} = live(conn, ~p"/admin/posts")
      assert {:ok, _view, _html} = live(conn, ~p"/admin/settings")
      assert {:ok, _view, _html} = live(conn, ~p"/admin/money")
      assert {:ok, _view, _html} = live(conn, ~p"/admin/events")
      assert {:ok, _view, _html} = live(conn, ~p"/admin/media")
      assert {:ok, _view, _html} = live(conn, ~p"/admin/users")
    end
  end
end
