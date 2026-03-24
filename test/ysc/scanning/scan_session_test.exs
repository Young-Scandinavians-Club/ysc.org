defmodule Ysc.Scanning.ScanSessionTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Scanning
  alias Ysc.Scanning.ScanSession

  defp admin_user, do: user_fixture(%{role: "admin"})

  describe "changeset/2" do
    test "valid membership session" do
      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Morning Membership Check",
          type: :membership
        })

      assert cs.valid?
    end

    test "valid event session with event_id" do
      admin = admin_user()
      event = event_fixture(%{organizer_id: admin.id})

      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Door Scan",
          type: :event,
          event_id: event.id
        })

      assert cs.valid?
    end

    test "requires name" do
      cs = ScanSession.changeset(%ScanSession{}, %{type: :membership})
      refute cs.valid?
      assert %{name: [_ | _]} = errors_on(cs)
    end

    test "requires type" do
      cs = ScanSession.changeset(%ScanSession{}, %{name: "Scan"})
      refute cs.valid?
      assert %{type: [_ | _]} = errors_on(cs)
    end

    test "requires event_id when type is :event" do
      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Event Scan",
          type: :event
        })

      refute cs.valid?
      assert %{event_id: [_ | _]} = errors_on(cs)
    end

    test "does not require event_id when type is :membership" do
      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Membership Scan",
          type: :membership
        })

      assert cs.valid?
      refute Map.has_key?(errors_on(cs), :event_id)
    end

    test "rejects event_id on membership sessions" do
      admin = admin_user()
      event = event_fixture(%{organizer_id: admin.id})

      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Membership Scan",
          type: :membership,
          event_id: event.id
        })

      refute cs.valid?
      assert %{event_id: [_ | _]} = errors_on(cs)
    end
  end

  describe "create_session/1 via Scanning context" do
    test "requires created_by_id" do
      {:error, changeset} =
        Scanning.create_session(%{name: "Scan", type: :membership})

      assert %{created_by_id: [_ | _]} = errors_on(changeset)
    end

    test "creates a valid session with created_by_id" do
      admin = admin_user()

      assert {:ok, session} =
               Scanning.create_session(%{
                 name: "Morning Scan",
                 type: :membership,
                 created_by_id: admin.id
               })

      assert session.created_by_id == admin.id
    end
  end

  describe "close_changeset/1" do
    test "sets closed_at to the current UTC time" do
      admin = admin_user()

      {:ok, session} =
        Scanning.create_session(%{
          name: "To Close",
          type: :membership,
          created_by_id: admin.id
        })

      assert is_nil(session.closed_at)

      cs = ScanSession.close_changeset(session)
      assert cs.valid?

      closed_at = get_change(cs, :closed_at)
      assert closed_at != nil
      assert closed_at.time_zone == "Etc/UTC"
      assert abs(DateTime.diff(DateTime.utc_now(), closed_at)) < 5
    end
  end
end
