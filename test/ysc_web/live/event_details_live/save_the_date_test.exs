defmodule YscWeb.EventDetailsLive.SaveTheDateTest do
  @moduledoc """
  Tests for the Save the Date notification opt-in UI on the event details page.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.TestDataFactory
  import Mox
  import EventDetailsLiveHelpers

  alias Ysc.Events

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

    {:ok, conn: conn}
  end

  defp tbd_event(opts \\ []) do
    event_with_state(
      :upcoming,
      Keyword.merge([with_image: true, attrs: %{tickets_tbd: true}], opts)
    )
  end

  describe "save the date badge" do
    test "displays 'Save the Date' badge when tickets_tbd is true", %{
      conn: conn
    } do
      event = tbd_event()
      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Save the Date"
    end

    test "does not display 'Save the Date' badge when tickets_tbd is false", %{
      conn: conn
    } do
      event = event_with_state(:upcoming, with_image: true)
      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      refute html =~ "Save the Date"
    end
  end

  describe "unauthenticated user on a save-the-date event" do
    test "sees 'Tickets Coming Soon' messaging", %{conn: conn} do
      event = tbd_event()
      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Tickets Coming Soon"
    end

    test "sees 'Sign in to get notified' link", %{conn: conn} do
      event = tbd_event()
      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Sign in to get notified"
    end

    test "'Sign in to get notified' link points to login with redirect_to param",
         %{conn: conn} do
      event = tbd_event()
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      redirect_path = ~p"/events/#{event.id}"
      expected_href = ~p"/users/log-in?redirect_to=#{redirect_path}"

      assert has_element?(view, "a[href='#{expected_href}']")
    end
  end

  describe "authenticated user on a save-the-date event" do
    setup %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = tbd_event()

      {:ok, %{conn: conn, user: user, event: event}}
    end

    test "sees 'Notify me' button when not subscribed", %{
      conn: conn,
      event: event
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      assert has_element?(view, "button[phx-click='subscribe-save-the-date']")
    end

    test "does not see the notify button when already subscribed", %{
      conn: conn,
      user: user,
      event: event
    } do
      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      refute has_element?(view, "button[phx-click='subscribe-save-the-date']")
      assert has_element?(view, "button[phx-click='unsubscribe-save-the-date']")
    end

    test "clicking 'Notify me' subscribes the user and updates the UI", %{
      conn: conn,
      user: user,
      event: event
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      refute Events.subscribed_to_event_notification?(
               event,
               user.id,
               "save_the_date"
             )

      render_click(view, "subscribe-save-the-date")

      assert Events.subscribed_to_event_notification?(
               event,
               user.id,
               "save_the_date"
             )

      refute has_element?(view, "button[phx-click='subscribe-save-the-date']")
      assert has_element?(view, "button[phx-click='unsubscribe-save-the-date']")
    end

    test "clicking 'Remove notification' unsubscribes the user and updates the UI",
         %{
           conn: conn,
           user: user,
           event: event
         } do
      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      render_click(view, "unsubscribe-save-the-date")

      refute Events.subscribed_to_event_notification?(
               event,
               user.id,
               "save_the_date"
             )

      assert has_element?(view, "button[phx-click='subscribe-save-the-date']")
      refute has_element?(view, "button[phx-click='unsubscribe-save-the-date']")
    end

    test "does not display the notify-me button on non-tbd events", %{
      conn: conn
    } do
      regular_event = event_with_state(:upcoming, with_image: true)
      {:ok, view, _html} = live(conn, ~p"/events/#{regular_event.id}")
      render_async(view)

      refute has_element?(view, "button[phx-click='subscribe-save-the-date']")
    end
  end

  describe "real-time update when admin clears tickets_tbd" do
    test "UI updates subscription state when event is updated via PubSub", %{
      conn: conn
    } do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = tbd_event()

      Events.subscribe_to_event_notification(event, user.id, "save_the_date")

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      render_async(view)

      # Before: subscribed state shown
      assert has_element?(view, "button[phx-click='unsubscribe-save-the-date']")

      # Admin clears tickets_tbd — broadcasts EventUpdated
      Events.set_tickets_tbd(event, false)

      # Allow the LiveView to process the PubSub message
      render_async(view)

      # After clearing TBD, the notify-me section is no longer shown
      refute has_element?(view, "button[phx-click='subscribe-save-the-date']")
      refute has_element?(view, "button[phx-click='unsubscribe-save-the-date']")
    end
  end
end
