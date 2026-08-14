defmodule YscWeb.AdminScannerRateLimitLiveTest do
  @moduledoc """
  Scanner rate-limit UI tests.

  Uses async: false because Hammer ETS state is shared across processes.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Scanning.QrToken

  defp create_admin(%{conn: conn}) do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp make_active_member do
    user = user_fixture()

    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()
    |> Ysc.Repo.reload!()
  end

  setup :create_admin

  test "scan_result is rate limited after many scans", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(conn, ~p"/admin/scanner")
    view |> element("button[phx-value-mode='membership']") |> render_click()

    view
    |> form("#scan-setup-form", %{session: %{name: "Rate limit"}})
    |> render_submit()

    member = make_active_member()
    token = QrToken.sign_membership(member.id)

    # Pre-fill the shared Hammer bucket at the limit so the next scan is denied
    # without racing other async tests through 20 prior hits.
    key = "scan:#{admin.id}"
    assert Ysc.ScanRateLimit.set(key, :timer.minutes(1), 20) == 20

    view |> render_hook("scan_result", %{"data" => token})

    html = render(view)
    assert html =~ "Too many scans" or html =~ "slow down"
  end
end
