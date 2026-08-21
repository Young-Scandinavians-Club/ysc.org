defmodule YscWeb.AdminEventsLive.TicketGrantFormTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures
  import Ysc.AccountsFixtures

  alias YscWeb.AdminEventsLive.TicketGrantForm
  alias YscWeb.AdminEventsLive.TicketTierManagement

  defp new_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns)
    }
  end

  describe "rendering" do
    test "shows the member search box when no user is selected" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      admin = user_fixture()

      html =
        render_component(TicketGrantForm, %{
          id: "grant-form",
          ticket_tier: tier,
          ticket_tier_id: tier.id,
          event_id: event.id,
          current_user: admin
        })

      # render_component/2 returns a static HTML string (no connected
      # LiveView process), so has_element?/3 doesn't apply here — LazyHTML
      # gives the same DOM-selector precision for static markup, matching
      # the pattern already used for rendered HTML in
      # test/ysc_web/emails/all_email_templates_test.exs.
      doc = LazyHTML.from_document(html)

      assert doc |> LazyHTML.query("#ticket-grant-form") |> Enum.any?()

      assert doc
             |> LazyHTML.query("#ticket-grant-user-autocomplete-input")
             |> Enum.any?()

      assert doc |> LazyHTML.query("#ticket_grant_quantity") |> Enum.any?()

      assert doc
             |> LazyHTML.query("#ticket_grant_skip_capacity[type=checkbox]")
             |> Enum.any?()

      assert doc
             |> LazyHTML.query("#ticket_grant_skip_sale_guards[type=checkbox]")
             |> Enum.any?()

      assert doc
             |> LazyHTML.query("#ticket_grant_send_email[type=checkbox]")
             |> Enum.any?()
    end
  end

  describe "update/2" do
    test "derives ticket_tier_id from a %TicketTier{} assign" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      admin = user_fixture()

      {:ok, socket} =
        TicketGrantForm.update(
          %{
            id: "grant-form",
            ticket_tier: tier,
            event_id: event.id,
            current_user: admin
          },
          new_socket()
        )

      assert socket.assigns.ticket_tier_id == tier.id
      assert socket.assigns.selected_user == nil
      assert socket.assigns.user_search == ""
      assert socket.assigns.user_search_results == []
    end

    test "falls back to an explicit ticket_tier_id assign when no ticket_tier is given" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      admin = user_fixture()

      {:ok, socket} =
        TicketGrantForm.update(
          %{
            id: "grant-form",
            ticket_tier_id: tier.id,
            event_id: event.id,
            current_user: admin
          },
          new_socket()
        )

      assert socket.assigns.ticket_tier_id == tier.id
    end

    test "does not reinitialize form state on subsequent updates" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      admin = user_fixture()
      member = user_fixture()

      {:ok, socket} =
        TicketGrantForm.update(
          %{
            id: "grant-form",
            ticket_tier: tier,
            event_id: event.id,
            current_user: admin
          },
          new_socket()
        )

      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "select-user",
          %{"id" => member.id},
          socket
        )

      {:ok, socket} =
        TicketGrantForm.update(
          %{
            id: "grant-form",
            ticket_tier: tier,
            event_id: event.id,
            current_user: admin
          },
          socket
        )

      # selected_user should survive the second update since the component
      # is already initialized and shouldn't reset its form.
      assert socket.assigns.selected_user.id == member.id
    end
  end

  describe "handle_event validate" do
    test "merges submitted params into the form" do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      admin = user_fixture()

      {:ok, socket} =
        TicketGrantForm.update(
          %{
            id: "grant-form",
            ticket_tier: tier,
            event_id: event.id,
            current_user: admin
          },
          new_socket()
        )

      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "validate",
          %{"ticket_grant" => %{"quantity" => "3"}},
          socket
        )

      assert socket.assigns.form.params["quantity"] == "3"
    end
  end

  describe "handle_event search-users" do
    setup do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      admin = user_fixture()

      {:ok, socket} =
        TicketGrantForm.update(
          %{
            id: "grant-form",
            ticket_tier: tier,
            event_id: event.id,
            current_user: admin
          },
          new_socket()
        )

      %{socket: socket, event: event, tier: tier, admin: admin}
    end

    test "returns matching users for queries with at least 2 characters", %{
      socket: socket
    } do
      member =
        user_fixture(%{first_name: "Searchable", last_name: "Member"})

      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "search-users",
          %{"value" => "Searchable"},
          socket
        )

      assert socket.assigns.user_search == "Searchable"

      assert Enum.any?(
               socket.assigns.user_search_results,
               &(&1.id == member.id)
             )
    end

    test "returns no results for queries shorter than 2 characters", %{
      socket: socket
    } do
      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "search-users",
          %{"value" => "a"},
          socket
        )

      assert socket.assigns.user_search_results == []
    end
  end

  describe "handle_event select-user and clear-user" do
    setup do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      admin = user_fixture()
      member = user_fixture()

      {:ok, socket} =
        TicketGrantForm.update(
          %{
            id: "grant-form",
            ticket_tier: tier,
            event_id: event.id,
            current_user: admin
          },
          new_socket()
        )

      %{socket: socket, member: member}
    end

    test "select-user sets the selected user and clears search state", %{
      socket: socket,
      member: member
    } do
      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "select-user",
          %{"id" => member.id},
          socket
        )

      assert socket.assigns.selected_user.id == member.id
      assert socket.assigns.user_search == ""
      assert socket.assigns.user_search_results == []
      assert socket.assigns.form.params["user_id"] == member.id
    end

    test "clear-user removes the selected user and the user_id param", %{
      socket: socket,
      member: member
    } do
      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "select-user",
          %{"id" => member.id},
          socket
        )

      {:noreply, socket} =
        TicketGrantForm.handle_event("clear-user", %{}, socket)

      assert socket.assigns.selected_user == nil
      assert socket.assigns.user_search == ""
      assert socket.assigns.user_search_results == []
      refute Map.has_key?(socket.assigns.form.params, "user_id")
    end
  end

  describe "handle_event save" do
    setup do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})
      admin = user_fixture()
      member = user_fixture()

      {:ok, socket} =
        TicketGrantForm.update(
          %{
            id: "grant-form",
            ticket_tier: tier,
            event_id: event.id,
            current_user: admin
          },
          new_socket()
        )

      %{socket: socket, event: event, tier: tier, admin: admin, member: member}
    end

    test "shows an error toast when no member is selected", %{socket: socket} do
      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "save",
          %{"ticket_grant" => %{"quantity" => "1"}},
          socket
        )

      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~
               "Select a member"
    end

    test "resets the quantity field when quantity is invalid", %{
      socket: socket,
      member: member
    } do
      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "select-user",
          %{"id" => member.id},
          socket
        )

      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "save",
          %{"ticket_grant" => %{"quantity" => "0"}},
          socket
        )

      assert socket.assigns.form.params["quantity"] == ""
    end

    test "grants tickets and notifies the parent component on success", %{
      socket: socket,
      event: event,
      member: member
    } do
      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "select-user",
          %{"id" => member.id},
          socket
        )

      {:noreply, _socket} =
        TicketGrantForm.handle_event(
          "save",
          %{
            "ticket_grant" => %{
              "quantity" => "1",
              "send_email" => "false"
            }
          },
          socket
        )

      assert_received {:phoenix, :send_update,
                       {{TicketTierManagement, "ticket-tier-management-" <> _},
                        %{close_grant_modal: true, grant_success: grant_success}}}

      assert grant_success.quantity == 1
      assert grant_success.user_name =~ member.first_name

      orders = Ysc.Tickets.list_user_ticket_orders(member.id)
      assert Enum.any?(orders, &(&1.event_id == event.id))
    end

    test "shows an error toast when the ticket tier no longer exists", %{
      socket: socket,
      member: member
    } do
      bad_tier_id = Ecto.ULID.generate()

      socket =
        put_in(socket.assigns.ticket_tier_id, bad_tier_id)

      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "select-user",
          %{"id" => member.id},
          socket
        )

      {:noreply, socket} =
        TicketGrantForm.handle_event(
          "save",
          %{"ticket_grant" => %{"quantity" => "1"}},
          socket
        )

      # Exact match (not a broad "tier" substring) so this test uniquely
      # verifies the :invalid_ticket_tier branch of grant_error_message/1
      # rather than any other tier-related error the form can surface.
      assert Phoenix.Flash.get(socket.assigns.flash, :error) ==
               "Invalid ticket tier."
    end
  end
end
