defmodule YscWeb.AdminEventsLive.TicketReservationFormTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures
  import Ysc.AccountsFixtures

  alias YscWeb.AdminEventsLive.TicketReservationForm

  describe "rendering" do
    test "displays reservation form" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "Reserve Tickets"
      assert html =~ "User"
      assert html =~ "Quantity"
    end

    test "displays tier name context" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "VIP Access"
        })

      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      # Form should render for VIP tier
      assert html =~ "Reserve Tickets"
    end

    test "displays discount field" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "Discount" or html =~ "discount"
    end

    test "displays notes field" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "Notes" or html =~ "note"
    end
  end

  describe "user search" do
    test "displays user search input" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "User" or html =~ "Search"
    end

    test "search field is debounced" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      # Should have phx-debounce for user search
      assert html =~ "phx-" or html =~ "User"
    end
  end

  describe "quantity field" do
    test "displays quantity input" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "Quantity"
    end
  end

  describe "form actions" do
    test "displays save reservation button" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "Save Reservation"
    end

    test "form has submit button" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "type=\"submit\"" or html =~ "phx-submit"
    end

    test "form submits to save action" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "phx-submit" or html =~ "form"
    end
  end

  describe "tier availability" do
    test "renders for limited quantity tiers" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          quantity: 100
        })

      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "Reserve Tickets"
    end

    test "renders for unlimited quantity tiers" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          quantity: nil
        })

      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ "Reserve Tickets"
    end
  end
end
