defmodule YscWeb.AdminCheckInPathsTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.ScanningFixtures

  alias YscWeb.AdminCheckInPaths

  describe "path_for_event/2 with preloaded open_sessions_by_event_id" do
    test "returns default event check-in when map has no session for event" do
      event_id = Ecto.ULID.generate()

      assert AdminCheckInPaths.path_for_event(event_id, %{}) ==
               "/admin/events/#{event_id}/check-in"
    end

    test "routes to membership desk for open event_membership session" do
      event_id = Ecto.ULID.generate()
      session_id = Ecto.ULID.generate()

      by_id = %{
        event_id => %{
          id: session_id,
          type: :event_membership,
          event_id: event_id
        }
      }

      assert AdminCheckInPaths.path_for_event(event_id, by_id) ==
               "/admin/membership-check-in/#{session_id}"
    end

    test "routes to ticket desk with scan_session_id for open event session" do
      event_id = Ecto.ULID.generate()
      session_id = Ecto.ULID.generate()

      by_id = %{
        event_id => %{
          id: session_id,
          type: :event,
          event_id: event_id
        }
      }

      assert AdminCheckInPaths.path_for_event(event_id, by_id) ==
               "/admin/events/#{event_id}/check-in?scan_session_id=#{session_id}"
    end

    test "prefers membership session from preloaded map when both types present" do
      event_id = Ecto.ULID.generate()
      membership_id = Ecto.ULID.generate()

      by_id = %{
        event_id => %{
          id: membership_id,
          type: :event_membership,
          event_id: event_id
        }
      }

      assert AdminCheckInPaths.path_for_event(event_id, by_id) =~
               "/admin/membership-check-in/#{membership_id}"
    end
  end

  describe "path_for_event/1" do
    test "queries open sessions and prefers membership desk" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})

      event_session = event_scan_session_fixture(event, admin)
      membership_session = event_membership_session_fixture(event, admin)

      path = AdminCheckInPaths.path_for_event(event.id)

      assert path == "/admin/membership-check-in/#{membership_session.id}"
      refute path =~ event_session.id
    end

    test "returns ticket desk path with session id when only event session is open" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_scan_session_fixture(event, admin)

      assert AdminCheckInPaths.path_for_event(event.id) ==
               "/admin/events/#{event.id}/check-in?scan_session_id=#{session.id}"
    end

    test "returns bare check-in path when no open session exists" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})

      assert AdminCheckInPaths.path_for_event(event.id) ==
               "/admin/events/#{event.id}/check-in"
    end
  end
end
