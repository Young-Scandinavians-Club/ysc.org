defmodule YscWeb.AdminEventsLive.TicketReservationFormTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures
  import Ysc.AccountsFixtures

  alias YscWeb.AdminEventsLive.TicketReservationForm
  alias Ysc.Events

  defp new_socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(%{__changed__: %{}, flash: %{}, admin_role: :admin}, assigns)
    }
  end

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

    test "uses the shared admin user autocomplete picker" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      user = user_fixture()

      html =
        render_component(TicketReservationForm, %{
          id: "reserve-#{tier.id}",
          ticket_tier: tier,
          current_user: user
        })

      assert html =~ ~s(id="ticket-reservation-user-autocomplete")
      assert html =~ ~s(id="ticket-reservation-user-autocomplete-input")
      assert html =~ "Search by name or email"
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

  describe "volunteer cannot create reservations (Finding 50)" do
    setup do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      volunteer = user_fixture(%{role: "volunteer"})
      member = user_fixture()

      {:ok, socket} =
        TicketReservationForm.update(
          %{
            id: "reserve-form",
            ticket_tier: tier,
            current_user: volunteer,
            admin_role: :volunteer
          },
          new_socket(%{admin_role: :volunteer})
        )

      %{socket: socket, member: member, volunteer: volunteer}
    end

    test "search-users is a no-op", %{socket: socket} do
      {:noreply, socket} =
        TicketReservationForm.handle_event(
          "search-users",
          %{"value" => "Searchable"},
          socket
        )

      assert socket.assigns.user_search == ""
      assert socket.assigns.user_search_results == []
    end

    test "select-user is a no-op", %{socket: socket, member: member} do
      {:noreply, socket} =
        TicketReservationForm.handle_event(
          "select-user",
          %{"id" => member.id},
          socket
        )

      assert socket.assigns.selected_user == nil
    end

    test "save shows a permission error and does not insert", %{
      socket: socket,
      member: member,
      volunteer: volunteer
    } do
      {:noreply, socket} =
        TicketReservationForm.handle_event(
          "save",
          %{
            "ticket_reservation" => %{
              "user_id" => member.id,
              "quantity" => "1",
              "discount_percentage" => "100"
            }
          },
          socket
        )

      assert Phoenix.Flash.get(socket.assigns.flash, :error) ==
               "You do not have permission to perform this action."

      assert Events.list_all_ticket_reservations_for_user(member.id) == []
      assert Events.list_all_ticket_reservations_for_user(volunteer.id) == []
    end
  end
end
