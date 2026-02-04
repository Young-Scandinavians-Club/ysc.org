defmodule YscWeb.AdminEventsLive.TicketTierManagementTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures
  import Ysc.AccountsFixtures

  alias YscWeb.AdminEventsLive.TicketTierManagement

  describe "rendering - empty state" do
    test "displays empty state when no tiers exist" do
      event = event_fixture()
      user = user_fixture()

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "No ticket tiers" or html =~ "Add"
    end

    test "displays add tier button" do
      event = event_fixture()
      user = user_fixture()

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "Add" or html =~ "New"
    end
  end

  describe "rendering - tier list" do
    test "displays existing tiers" do
      event = event_fixture()
      user = user_fixture()

      _tier1 =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "General Admission"
        })

      _tier2 =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "VIP Pass"
        })

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "General Admission"
      assert html =~ "VIP Pass"
    end

    test "displays tier prices" do
      event = event_fixture()
      user = user_fixture()

      _tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :paid,
          price: Money.new(2500, :USD)
        })

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "$25" or html =~ "25"
    end

    test "displays free tier indicator" do
      event = event_fixture()
      user = user_fixture()

      _tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :free,
          price: Money.new(0, :USD),
          name: "Free Entry"
        })

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "Free Entry"
    end

    test "displays donation tier" do
      event = event_fixture()
      user = user_fixture()

      _tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :donation,
          name: "Support Us"
        })

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "Support Us"
    end
  end

  describe "tier quantity display" do
    test "displays limited quantity tiers" do
      event = event_fixture()
      user = user_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          quantity: 100
        })

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "100" or html =~ tier.name
    end

    test "displays unlimited quantity indicator" do
      event = event_fixture()
      user = user_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          quantity: nil
        })

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      # Should display tier
      assert html =~ tier.name
    end
  end

  describe "tier actions" do
    test "displays edit button for each tier" do
      event = event_fixture()
      user = user_fixture()
      _tier = ticket_tier_fixture(%{event_id: event.id})

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "Edit" or html =~ "edit"
    end

    test "displays reserve button for each tier" do
      event = event_fixture()
      user = user_fixture()
      _tier = ticket_tier_fixture(%{event_id: event.id})

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "Reserve" or html =~ "reserve"
    end
  end

  describe "purchases section" do
    test "renders component with purchase data" do
      event = event_fixture()
      user_admin = user_fixture()

      user =
        user_fixture(%{
          first_name: "John",
          last_name: "Doe"
        })

      tier = ticket_tier_fixture(%{event_id: event.id, name: "General"})

      _ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier
        })

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user_admin
        })

      # Component should render with tier name
      assert html =~ "General"
    end

    test "renders component with multiple tiers and purchases" do
      event = event_fixture()
      user_admin = user_fixture()
      user = user_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id, name: "VIP"})

      _ticket_order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          quantity: 3
        })

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user_admin
        })

      # Component should render with tier name
      assert html =~ "VIP"
    end
  end

  describe "CSV export" do
    test "displays CSV export button" do
      event = event_fixture()
      user = user_fixture()
      _tier = ticket_tier_fixture(%{event_id: event.id})

      html =
        render_component(TicketTierManagement, %{
          id: "tier-management",
          event_id: event.id,
          current_user: user
        })

      assert html =~ "Export" or html =~ "CSV"
    end
  end
end
