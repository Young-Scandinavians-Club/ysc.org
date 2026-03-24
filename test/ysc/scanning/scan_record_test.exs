defmodule Ysc.Scanning.ScanRecordTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Scanning.ScanRecord

  defp session, do: scan_session_fixture()

  describe "changeset/2" do
    test "valid record with just session_id and result" do
      s = session()

      cs =
        ScanRecord.changeset(%ScanRecord{}, %{
          scan_session_id: s.id,
          result: :success
        })

      assert cs.valid?
    end

    test "valid record with all optional fields" do
      s = session()
      user = user_fixture()

      cs =
        ScanRecord.changeset(%ScanRecord{}, %{
          scan_session_id: s.id,
          user_id: user.id,
          result: :success,
          checkin_type: :individual,
          membership_status: "active",
          membership_type: "lifetime"
        })

      assert cs.valid?
    end

    test "requires scan_session_id" do
      cs = ScanRecord.changeset(%ScanRecord{}, %{result: :success})
      refute cs.valid?
      assert %{scan_session_id: [_ | _]} = errors_on(cs)
    end

    test "requires result" do
      s = session()
      cs = ScanRecord.changeset(%ScanRecord{}, %{scan_session_id: s.id})
      refute cs.valid?
      assert %{result: [_ | _]} = errors_on(cs)
    end

    test "accepts :invalid result" do
      s = session()

      cs =
        ScanRecord.changeset(%ScanRecord{}, %{
          scan_session_id: s.id,
          result: :invalid
        })

      assert cs.valid?
    end

    test "accepts :already_scanned result" do
      s = session()

      cs =
        ScanRecord.changeset(%ScanRecord{}, %{
          scan_session_id: s.id,
          result: :already_scanned
        })

      assert cs.valid?
    end
  end
end
