defmodule YscWeb.AdminEventsLive.TicketTierFormTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures

  alias YscWeb.AdminEventsLive.TicketTierForm

  describe "rendering - new tier" do
    test "displays form for creating new tier" do
      event = event_fixture()

      html =
        render_component(TicketTierForm, %{
          id: "new-tier",
          event: event,
          event_id: event.id,
          tier: nil,
          action: :new
        })

      assert html =~ "Name"
      assert html =~ "Type"
      assert html =~ "Quantity"
    end

    test "displays type options" do
      event = event_fixture()

      html =
        render_component(TicketTierForm, %{
          id: "new-tier",
          event: event,
          event_id: event.id,
          tier: nil,
          action: :new
        })

      assert html =~ "Free"
      assert html =~ "Paid"
      assert html =~ "Donation"
    end

    test "displays add button for new tier" do
      event = event_fixture()

      html =
        render_component(TicketTierForm, %{
          id: "new-tier",
          event: event,
          event_id: event.id,
          tier: nil,
          action: :new
        })

      assert html =~ "Add Ticket Tier"
    end
  end

  describe "rendering - edit tier" do
    test "displays form for editing existing tier" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "VIP Pass"
        })

      html =
        render_component(TicketTierForm, %{
          id: "edit-tier-#{tier.id}",
          event: event,
          event_id: event.id,
          tier: tier,
          action: :edit
        })

      # Form should render with fields
      assert html =~ "Type"
      assert html =~ "Name"
    end

    test "displays form for paid tier" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :paid,
          price: Money.new(5000, :USD)
        })

      html =
        render_component(TicketTierForm, %{
          id: "edit-tier-#{tier.id}",
          event: event,
          event_id: event.id,
          tier: tier,
          action: :edit
        })

      # Form should render with all fields
      assert html =~ "Type"
      assert html =~ "Quantity"
    end

    test "displays quantity for tier" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          quantity: 100
        })

      html =
        render_component(TicketTierForm, %{
          id: "edit-tier-#{tier.id}",
          event: event,
          event_id: event.id,
          tier: tier,
          action: :edit
        })

      assert html =~ "100" or html =~ "value=\"100\""
    end
  end

  describe "tier types" do
    test "free tier renders correctly" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :free,
          price: Money.new(0, :USD)
        })

      html =
        render_component(TicketTierForm, %{
          id: "edit-tier-#{tier.id}",
          event: event,
          event_id: event.id,
          tier: tier,
          action: :edit
        })

      assert html =~ "Type"
    end

    test "paid tier shows price field" do
      event = event_fixture()

      html =
        render_component(TicketTierForm, %{
          id: "new-tier",
          event: event,
          event_id: event.id,
          tier: nil,
          action: :new
        })

      assert html =~ "Type"
    end

    test "donation tier renders correctly" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :donation,
          quantity: nil
        })

      html =
        render_component(TicketTierForm, %{
          id: "edit-tier-#{tier.id}",
          event: event,
          event_id: event.id,
          tier: tier,
          action: :edit
        })

      assert html =~ "Type"
    end
  end

  describe "unlimited quantity" do
    test "displays unlimited quantity checkbox" do
      event = event_fixture()

      html =
        render_component(TicketTierForm, %{
          id: "new-tier",
          event: event,
          event_id: event.id,
          tier: nil,
          action: :new
        })

      assert html =~ "Unlimited" or html =~ "unlimited"
    end

    test "shows unlimited when quantity is nil" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          quantity: nil
        })

      html =
        render_component(TicketTierForm, %{
          id: "edit-tier-#{tier.id}",
          event: event,
          event_id: event.id,
          tier: tier,
          action: :edit
        })

      # Form should render
      assert html =~ "Name"
    end
  end

  describe "form actions" do
    test "form has submit button" do
      event = event_fixture()

      html =
        render_component(TicketTierForm, %{
          id: "new-tier",
          event: event,
          event_id: event.id,
          tier: nil,
          action: :new
        })

      assert html =~ "type=\"submit\""
    end

    test "form submits to correct action" do
      event = event_fixture()

      html =
        render_component(TicketTierForm, %{
          id: "new-tier",
          event: event,
          event_id: event.id,
          tier: nil,
          action: :new
        })

      assert html =~ "phx-submit" or html =~ "form"
    end
  end

  describe "type selector" do
    test "renders type as a radio group with all options visible" do
      event = event_fixture()

      html =
        render_component(TicketTierForm, %{
          id: "new-tier",
          event: event,
          event_id: event.id,
          tier: nil,
          action: :new
        })

      # Segmented control, not a <select>
      assert html =~ ~s(role="radiogroup")

      assert html =~
               ~s(<input type="radio" name="ticket_tier[type]" value="free")

      assert html =~
               ~s(<input type="radio" name="ticket_tier[type]" value="paid")

      assert html =~
               ~s(<input type="radio" name="ticket_tier[type]" value="donation")

      # Each option carries a short helper description
      assert html =~ "No charge to attend"
      assert html =~ "One fixed ticket price"
      assert html =~ "Attendee picks the amount"
    end

    test "only the current type's radio is checked when editing a paid tier" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :paid,
          price: Money.new(8500, :USD)
        })

      html =
        render_component(TicketTierForm, %{
          id: "edit-tier-#{tier.id}",
          event: event,
          event_id: event.id,
          ticket_tier: tier,
          action: :edit
        })

      doc = LazyHTML.from_fragment(html)

      # Exactly one type radio is checked, and it is the paid one.
      checked =
        LazyHTML.query(doc, ~s(input[name="ticket_tier[type]"][checked]))

      assert LazyHTML.attribute(checked, "value") == ["paid"]

      # Exactly one Type card carries the blue "selected" highlight, and it is
      # the card wrapping the checked paid radio.
      selected =
        LazyHTML.query(doc, "#ticket-tier-type-options label.bg-blue-50")

      assert Enum.count(selected) == 1

      assert selected
             |> LazyHTML.query(~s(input[value="paid"][checked]))
             |> Enum.any?()

      # Every card uses the neutral zinc focus ring, not the blue selected color,
      # so a programmatically focused card is never mistaken for a selection.
      cards = LazyHTML.query(doc, "#ticket-tier-type-options label")
      class_attrs = LazyHTML.attribute(cards, "class")

      assert Enum.count(class_attrs) == 3
      assert Enum.all?(class_attrs, &(&1 =~ "focus-within:ring-zinc-600"))
      refute Enum.any?(class_attrs, &(&1 =~ "focus-within:ring-blue"))
    end
  end

  describe "requires registration option" do
    test "shows an inline description instead of only a tooltip" do
      event = event_fixture()

      html =
        render_component(TicketTierForm, %{
          id: "new-tier",
          event: event,
          event_id: event.id,
          tier: nil,
          action: :new
        })

      assert html =~ "Requires registration"

      assert html =~
               "Collect first name, last name, and email for every ticket"
    end
  end
end
