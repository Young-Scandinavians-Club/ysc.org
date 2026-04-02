defmodule Ysc.MembershipCheckInTest do
  @moduledoc """
  Tests for the membership check-in (event_membership session) functionality
  in Ysc.Scanning.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Scanning
  alias Ysc.Repo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp make_active_member do
    user = user_fixture()

    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
    |> Repo.reload!()
  end

  defp make_inactive_member do
    user_fixture()
  end

  # ---------------------------------------------------------------------------
  # Session creation: event_membership type
  # ---------------------------------------------------------------------------

  describe "create_session/1 with event_membership type" do
    test "creates an event_membership session with event_id" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})

      assert {:ok, session} =
               Scanning.create_session(%{
                 name: "Membership Door",
                 type: :event_membership,
                 event_id: event.id,
                 created_by_id: admin.id
               })

      assert session.type == :event_membership
      assert session.event_id == event.id
    end

    test "rejects event_membership session without event_id" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, changeset} =
               Scanning.create_session(%{
                 name: "Bad Session",
                 type: :event_membership,
                 created_by_id: admin.id
               })

      assert %{event_id: ["is required for event scan sessions"]} =
               errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # check_in_member/3
  # ---------------------------------------------------------------------------

  describe "check_in_member/3" do
    setup do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)
      member = make_active_member()
      %{admin: admin, session: session, member: member}
    end

    test "checks in a user with active membership", %{
      admin: admin,
      session: session,
      member: member
    } do
      assert {:ok, check_in} = Scanning.check_in_member(session, member, admin)

      assert check_in.user_id == member.id
      assert check_in.scan_session_id == session.id
      assert check_in.checked_in_by_id == admin.id
      assert check_in.membership_status == "active"
    end

    test "checks in a user with inactive membership, recording inactive status",
         %{
           admin: admin,
           session: session
         } do
      inactive_user = make_inactive_member()

      assert {:ok, check_in} =
               Scanning.check_in_member(session, inactive_user, admin)

      assert check_in.membership_status == "inactive"
    end

    test "returns error when user is already checked in", %{
      admin: admin,
      session: session,
      member: member
    } do
      assert {:ok, _} = Scanning.check_in_member(session, member, admin)

      assert {:error, :already_checked_in, _message} =
               Scanning.check_in_member(session, member, admin)
    end

    test "broadcasts MemberCheckedIn via PubSub", %{
      admin: admin,
      session: session,
      member: member
    } do
      Scanning.subscribe_membership_checkin(session.id)

      assert {:ok, _check_in} = Scanning.check_in_member(session, member, admin)

      assert_receive {Scanning,
                      %Ysc.MessagePassingEvents.MemberCheckedIn{session_id: sid}}

      assert sid == session.id
    end
  end

  # ---------------------------------------------------------------------------
  # undo_member_check_in/2
  # ---------------------------------------------------------------------------

  describe "undo_member_check_in/2" do
    setup do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)
      member = make_active_member()
      {:ok, _} = Scanning.check_in_member(session, member, admin)
      %{admin: admin, session: session, member: member}
    end

    test "removes a checked-in member", %{session: session, member: member} do
      assert Scanning.member_checked_in?(session.id, member.id)

      assert {:ok, :removed} =
               Scanning.undo_member_check_in(session.id, member.id)

      refute Scanning.member_checked_in?(session.id, member.id)
    end

    test "returns error when check-in not found", %{session: session} do
      non_member = user_fixture()

      assert {:error, :not_found, _message} =
               Scanning.undo_member_check_in(session.id, non_member.id)
    end

    test "broadcasts MemberCheckInUndone via PubSub", %{
      session: session,
      member: member
    } do
      Scanning.subscribe_membership_checkin(session.id)

      assert {:ok, :removed} =
               Scanning.undo_member_check_in(session.id, member.id)

      assert_receive {Scanning,
                      %Ysc.MessagePassingEvents.MemberCheckInUndone{
                        session_id: sid,
                        user_id: uid
                      }}

      assert sid == session.id
      assert uid == member.id
    end
  end

  # ---------------------------------------------------------------------------
  # list_membership_check_ins/2
  # ---------------------------------------------------------------------------

  describe "list_membership_check_ins/2" do
    setup do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)
      %{admin: admin, session: session}
    end

    test "returns empty list when no check-ins", %{session: session} do
      assert [] = Scanning.list_membership_check_ins(session.id)
    end

    test "returns all checked-in members", %{
      admin: admin,
      session: session
    } do
      m1 = make_active_member()
      m2 = make_active_member()
      {:ok, _} = Scanning.check_in_member(session, m1, admin)
      {:ok, _} = Scanning.check_in_member(session, m2, admin)

      check_ins = Scanning.list_membership_check_ins(session.id)
      assert length(check_ins) == 2
      ids = Enum.map(check_ins, & &1.user_id)
      assert m1.id in ids
      assert m2.id in ids
    end

    test "filters by search query on name and email", %{
      admin: admin,
      session: session
    } do
      m1 = make_active_member()

      m2 =
        user_fixture(%{
          first_name: "Unique",
          last_name: "Searchable",
          email: "unique_searchable@example.com"
        })

      {:ok, _} = Scanning.check_in_member(session, m1, admin)
      {:ok, _} = Scanning.check_in_member(session, m2, admin)

      results = Scanning.list_membership_check_ins(session.id, "Unique")
      assert length(results) == 1
      assert hd(results).user_id == m2.id
    end
  end

  # ---------------------------------------------------------------------------
  # membership_check_in_count/1
  # ---------------------------------------------------------------------------

  describe "membership_check_in_count/1" do
    test "returns 0 for empty session" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)

      assert 0 = Scanning.membership_check_in_count(session.id)
    end

    test "returns correct count after check-ins" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)

      m1 = make_active_member()
      m2 = make_active_member()
      {:ok, _} = Scanning.check_in_member(session, m1, admin)
      {:ok, _} = Scanning.check_in_member(session, m2, admin)

      assert 2 = Scanning.membership_check_in_count(session.id)
    end
  end

  # ---------------------------------------------------------------------------
  # search_users_for_checkin/2
  # ---------------------------------------------------------------------------

  describe "search_users_for_checkin/2" do
    setup do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)
      %{admin: admin, session: session}
    end

    test "returns empty list for blank query", %{session: session} do
      assert [] = Scanning.search_users_for_checkin(session.id, "")
    end

    test "enriches results with membership_status and checked_in? flag", %{
      admin: admin,
      session: session
    } do
      member = make_active_member()
      {:ok, _} = Scanning.check_in_member(session, member, admin)

      query = member.email
      results = Scanning.search_users_for_checkin(session.id, query)
      assert results != []

      result = Enum.find(results, &(&1.user.id == member.id))
      assert result.membership_status == :active
      assert result.checked_in? == true
    end

    test "marks non-checked-in users as checked_in? false", %{session: session} do
      member = make_active_member()
      query = member.email
      results = Scanning.search_users_for_checkin(session.id, query)

      result = Enum.find(results, &(&1.user.id == member.id))
      assert result != nil
      assert result.checked_in? == false
    end

    test "marks inactive members correctly", %{session: session} do
      inactive = make_inactive_member()
      results = Scanning.search_users_for_checkin(session.id, inactive.email)

      result = Enum.find(results, &(&1.user.id == inactive.id))
      assert result != nil
      assert result.membership_status == :inactive
    end
  end

  # ---------------------------------------------------------------------------
  # get_open_membership_sessions/0
  # ---------------------------------------------------------------------------

  describe "get_open_membership_sessions/0" do
    test "returns only open event_membership sessions" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})

      session = event_membership_session_fixture(event, admin)

      open = Scanning.get_open_membership_sessions()
      ids = Enum.map(open, & &1.id)
      assert session.id in ids
    end

    test "does not return regular membership or event sessions" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})

      _ms = Ysc.ScanningFixtures.scan_session_fixture(%{created_by: admin})
      _es = Ysc.ScanningFixtures.event_scan_session_fixture(event, admin)

      open = Scanning.get_open_membership_sessions()

      Enum.each(open, fn s ->
        assert s.type == :event_membership
      end)
    end

    test "does not return closed sessions" do
      admin = user_fixture(%{role: "admin"})
      event = event_fixture(%{organizer_id: admin.id})
      session = event_membership_session_fixture(event, admin)

      Scanning.close_session(session.id)

      open = Scanning.get_open_membership_sessions()
      ids = Enum.map(open, & &1.id)
      refute session.id in ids
    end
  end
end
