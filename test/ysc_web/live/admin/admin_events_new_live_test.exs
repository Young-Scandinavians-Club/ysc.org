defmodule YscWeb.AdminEventsNewLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Agendas
  alias Ysc.Events
  alias Ysc.MessagePassingEvents

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  describe "hosts - create_event defaults" do
    setup [:create_admin]

    test "newly created event has organizer as default host", %{admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      hosts = Events.list_event_hosts(event)

      assert length(hosts) == 1
      assert hd(hosts).id == admin.id
    end
  end

  describe "hosts - edit page UI" do
    setup [:create_admin]

    test "add agenda inserts an agenda card", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      refute has_element?(view, "#agendas .drag-handle")

      assert view |> element("#add-agenda-button") |> render_click()

      assert has_element?(view, "#agendas .drag-handle")
    end

    test "shows Hosts section on edit tab", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#hosts-section")
      assert has_element?(view, "#host-search-input")
    end

    test "shows host search input", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#host-search-input")
    end

    test "renders organizer as a host pill on mount", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#host-#{admin.id}")
    end

    test "renders each current host with a remove button", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#host-#{admin.id}")

      assert has_element?(
               view,
               "#host-#{admin.id} button[phx-click='remove-host']"
             )
    end

    test "does not show hosts section on tickets tab", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, _view, html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      refute html =~ "event-hosts-manager"
    end
  end

  describe "agendas - PubSub when switching events" do
    setup [:create_admin]

    test "does not apply agenda updates from a previous event after live-patching to another event",
         %{conn: conn, admin: admin} do
      event_a = event_fixture(%{organizer_id: admin.id})
      event_b = event_fixture(%{organizer_id: admin.id})

      {:ok, agenda_a} =
        Agendas.create_agenda(event_a, %{title: "Agenda on event A only"})

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event_a.id}/edit")
      assert has_element?(view, "#agendas li[data-id='#{agenda_a.id}']")

      _html = render_patch(view, ~p"/admin/events/#{event_b.id}/edit")
      refute has_element?(view, "#agendas li[data-id='#{agenda_a.id}']")

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "agendas:#{event_a.id}",
        {Ysc.Agendas, %MessagePassingEvents.AgendaAdded{agenda: agenda_a}}
      )

      _html = render(view)
      refute has_element?(view, "#agendas li[data-id='#{agenda_a.id}']")
    end
  end

  describe "hosts - search-hosts event" do
    setup [:create_admin]

    test "empty query returns no results and clears dropdown", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input") |> render_keyup(%{"value" => ""})

      refute has_element?(view, "#host-search-results")
    end

    test "query matching a user shows them in the dropdown", %{
      conn: conn,
      admin: admin
    } do
      other_user = user_fixture(%{first_name: "Solvieg", last_name: "Eriksson"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input")
      |> render_keyup(%{"value" => "Solvieg"})

      assert has_element?(view, "#host-result-#{other_user.id}")
      assert has_element?(view, "#host-result-#{other_user.id}", "Solvieg")
    end

    test "query matching no user shows no-results message", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input")
      |> render_keyup(%{"value" => "zzznomatch99xyz"})

      refute has_element?(view, "#host-search-results")
      assert has_element?(view, "#event-hosts-manager", "No members found")
    end

    test "matching user who is already a host shows check-circle icon", %{
      conn: conn,
      admin: admin
    } do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input")
      |> render_keyup(%{"value" => admin.first_name})

      assert has_element?(view, "#host-result-#{admin.id} .host-status-icon")
    end
  end

  describe "hosts - add-host event" do
    setup [:create_admin]

    test "adds a new user as host and shows them in the list", %{
      conn: conn,
      admin: admin
    } do
      other_user = user_fixture(%{first_name: "Bjorn", last_name: "Lindqvist"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "add-host", %{"user-id" => other_user.id})

      assert has_element?(view, "#host-#{other_user.id}")
    end

    test "persists the added host to the database", %{conn: conn, admin: admin} do
      other_user = user_fixture(%{first_name: "Astrid", last_name: "Berg"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "add-host", %{"user-id" => other_user.id})

      hosts = Events.list_event_hosts(event)
      host_ids = Enum.map(hosts, & &1.id)
      assert other_user.id in host_ids
    end

    test "adding same user twice does not duplicate them", %{
      conn: conn,
      admin: admin
    } do
      other_user = user_fixture(%{first_name: "Ingrid", last_name: "Holm"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "add-host", %{"user-id" => other_user.id})
      render_click(view, "add-host", %{"user-id" => other_user.id})

      hosts = Events.list_event_hosts(event)
      assert length(Enum.filter(hosts, &(&1.id == other_user.id))) == 1
    end

    test "clears search query and results after adding a host", %{
      conn: conn,
      admin: admin
    } do
      other_user = user_fixture(%{first_name: "Gunnar", last_name: "Strand"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      element(view, "#host-search-input")
      |> render_keyup(%{"value" => "Gunnar"})

      element(view, "#host-result-#{other_user.id} button") |> render_click()

      refute has_element?(view, "#host-search-results")
    end

    test "does nothing for a nonexistent user id", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      initial_hosts = Events.list_event_hosts(event)

      render_click(view, "add-host", %{"user-id" => Ecto.ULID.generate()})

      assert Events.list_event_hosts(event) == initial_hosts
    end
  end

  describe "hosts - remove-host event" do
    setup [:create_admin]

    test "removes a host from the list", %{conn: conn, admin: admin} do
      other_user = user_fixture(%{first_name: "Freya", last_name: "Dahl"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, _} = Events.add_event_host(event, other_user)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      assert has_element?(view, "#host-#{other_user.id}")

      element(view, "#host-#{other_user.id} button[phx-click='remove-host']")
      |> render_click()

      refute has_element?(view, "#host-#{other_user.id}")
    end

    test "persists the removal to the database", %{conn: conn, admin: admin} do
      other_user = user_fixture(%{first_name: "Leif", last_name: "Carlsson"})
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, _} = Events.add_event_host(event, other_user)

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "remove-host", %{"user-id" => other_user.id})

      hosts = Events.list_event_hosts(event)
      refute Enum.any?(hosts, &(&1.id == other_user.id))
    end

    test "can remove the organizer from hosts", %{conn: conn, admin: admin} do
      event = event_fixture(%{organizer_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/edit")

      render_click(view, "remove-host", %{"user-id" => admin.id})

      refute has_element?(view, "#host-#{admin.id}")
      assert Events.list_event_hosts(event) == []
    end
  end

  describe "Admin Events New/Edit - Stale Entry Bug Fix" do
    setup [:create_admin]

    test "reproduces original bug: concurrent detail edits during capacity change",
         %{
           conn: conn,
           admin: admin
         } do
      # This test reproduces the EXACT scenario from the bug report:
      # User is editing event details (title, description, etc.) which auto-saves,
      # then tries to edit ticket tier capacity, which would fail with stale entry error

      event =
        event_fixture(%{
          title: "Original Title",
          description: "Original description",
          organizer_id: admin.id,
          max_attendees: 100
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # Simulate what happens when editing event details on the "Event Details" tab
      # (the auto-save increments lock_version multiple times)
      {:ok, event} = Events.update_event(event, %{title: "Auto-save 1"})
      {:ok, event} = Events.update_event(event, %{description: "Auto-save 2"})
      {:ok, _event} = Events.update_event(event, %{title: "Auto-save 3"})

      # Now on the "Tickets" tab, try to change capacity
      # Before the fix, this would fail with Ecto.StaleEntryError because
      # socket.assigns[:event] had lock_version from mount time
      form = element(view, "#capacity_form")

      # This should NOT crash with stale entry error
      result =
        form
        |> render_change(%{
          "event" => %{
            "max_attendees" => "250"
          }
        })

      # Verify it worked
      assert result
      reloaded_event = Events.get_event!(event.id)
      assert reloaded_event.max_attendees == 250
      assert reloaded_event.title == "Auto-save 3"
    end

    test "handles concurrent event updates without stale entry error on capacity toggle",
         %{
           conn: conn,
           admin: admin
         } do
      # This test reproduces the original bug: editing event details while also
      # editing capacity would cause a stale entry error because the capacity
      # handlers weren't reloading the event before updating.

      event =
        event_fixture(%{
          title: "Test Event",
          description: "Original description",
          organizer_id: admin.id,
          max_attendees: 100
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # Simulate a background update (like another tab or auto-save)
      # This increments lock_version in the database
      {:ok, _updated_event} =
        Events.update_event(event, %{
          title: "Updated Title",
          description: "Updated description"
        })

      # Now try to toggle capacity - this would have raised Ecto.StaleEntryError
      # before the fix, but should work now because we reload the event
      view
      |> element("input[type='checkbox'][name='event[unlimited_capacity]']")
      |> render_click()

      # Verify the capacity was updated (should be nil now for unlimited)
      reloaded_event = Events.get_event!(event.id)
      assert is_nil(reloaded_event.max_attendees)

      # Verify no crash occurred - the view is still functional
      assert render(view) =~ "Event Capacity"
    end

    test "handles validate-capacity with concurrent updates", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{
          title: "Capacity Test",
          organizer_id: admin.id,
          max_attendees: 100
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # Simulate background update
      {:ok, _} = Events.update_event(event, %{title: "Background Update"})

      # Try to change capacity - should not raise stale entry error
      form = element(view, "#capacity_form")

      assert form
             |> render_change(%{
               "event" => %{
                 "max_attendees" => "150"
               }
             })

      # Verify the capacity was updated
      reloaded_event = Events.get_event!(event.id)
      assert reloaded_event.max_attendees == 150
    end

    test "handles save-capacity with concurrent updates", %{
      conn: conn,
      admin: admin
    } do
      event =
        event_fixture(%{
          title: "Save Capacity Test",
          organizer_id: admin.id,
          max_attendees: 50
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      # Simulate background update
      {:ok, _} = Events.update_event(event, %{description: "Background change"})

      # Try to save capacity
      form = element(view, "#capacity_form")

      assert form
             |> render_submit(%{
               "event" => %{
                 "max_attendees" => "75"
               }
             })

      # Verify the capacity was updated successfully
      reloaded_event = Events.get_event!(event.id)
      assert reloaded_event.max_attendees == 75
    end

    test "multiple rapid capacity changes with concurrent event updates", %{
      conn: conn,
      admin: admin
    } do
      # This test simulates the real-world scenario where a user is editing
      # multiple fields rapidly while auto-save is updating in the background

      event =
        event_fixture(%{
          title: "Rapid Changes Test",
          organizer_id: admin.id,
          max_attendees: 100
        })

      {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

      form = element(view, "#capacity_form")

      # Make a capacity change
      form |> render_change(%{"event" => %{"max_attendees" => "150"}})

      # Background update happens
      {:ok, _} =
        Events.update_event(Events.get_event!(event.id), %{title: "Update 1"})

      # Another capacity change
      form |> render_change(%{"event" => %{"max_attendees" => "200"}})

      # Another background update
      {:ok, _} =
        Events.update_event(Events.get_event!(event.id), %{title: "Update 2"})

      # Final capacity change
      form |> render_change(%{"event" => %{"max_attendees" => "250"}})

      # Verify the final value is correct and no stale entry errors occurred
      reloaded_event = Events.get_event!(event.id)
      assert reloaded_event.max_attendees == 250
      assert reloaded_event.title == "Update 2"
    end
  end
end
