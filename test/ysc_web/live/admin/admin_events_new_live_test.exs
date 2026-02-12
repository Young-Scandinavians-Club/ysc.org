defmodule YscWeb.AdminEventsNewLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
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
