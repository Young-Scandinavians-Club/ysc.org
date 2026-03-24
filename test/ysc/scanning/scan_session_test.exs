defmodule Ysc.Scanning.ScanSessionTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Scanning.ScanSession

  defp admin_user, do: user_fixture(%{role: "admin"})

  describe "changeset/2" do
    test "valid membership session" do
      admin = admin_user()

      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Morning Membership Check",
          type: :membership,
          created_by_id: admin.id
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
          event_id: event.id,
          created_by_id: admin.id
        })

      assert cs.valid?
    end

    test "requires name" do
      admin = admin_user()

      cs =
        ScanSession.changeset(%ScanSession{}, %{
          type: :membership,
          created_by_id: admin.id
        })

      refute cs.valid?
      assert %{name: [_ | _]} = errors_on(cs)
    end

    test "requires type" do
      admin = admin_user()

      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Scan",
          created_by_id: admin.id
        })

      refute cs.valid?
      assert %{type: [_ | _]} = errors_on(cs)
    end

    test "requires created_by_id" do
      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Scan",
          type: :membership
        })

      refute cs.valid?
      assert %{created_by_id: [_ | _]} = errors_on(cs)
    end

    test "requires event_id when type is :event" do
      admin = admin_user()

      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Event Scan",
          type: :event,
          created_by_id: admin.id
        })

      refute cs.valid?
      assert %{event_id: [_ | _]} = errors_on(cs)
    end

    test "does not require event_id when type is :membership" do
      admin = admin_user()

      cs =
        ScanSession.changeset(%ScanSession{}, %{
          name: "Membership Scan",
          type: :membership,
          created_by_id: admin.id
        })

      assert cs.valid?
      refute Map.has_key?(errors_on(cs), :event_id)
    end
  end

  describe "close_changeset/1" do
    test "sets closed_at to the current UTC time" do
      admin = admin_user()

      {:ok, session} =
        %ScanSession{}
        |> ScanSession.changeset(%{
          name: "To Close",
          type: :membership,
          created_by_id: admin.id
        })
        |> Ysc.Repo.insert()

      assert is_nil(session.closed_at)

      cs = ScanSession.close_changeset(session)
      assert cs.valid?
      assert get_change(cs, :closed_at) != nil
    end
  end
end
