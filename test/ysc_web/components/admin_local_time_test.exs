defmodule YscWeb.AdminLocalTimeTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_local_time/1" do
    test "wires the LocalTime hook and ISO UTC timestamp" do
      assigns = %{datetime: ~U[2026-10-12 20:00:00Z]}

      html =
        rendered_to_string(~H"""
        <.admin_local_time id="outage-time-1" datetime={@datetime}>
          2026-10-12 20:00:00 UTC
        </.admin_local_time>
        """)

      assert html =~ ~s(id="outage-time-1")
      assert html =~ ~s(phx-hook="LocalTime")
      assert html =~ ~s(data-utc-time="2026-10-12T20:00:00Z")
      assert html =~ "2026-10-12 20:00:00 UTC"
      refute html =~ "phx-update"
    end

    test "forwards phx-update ignore and extra classes" do
      assigns = %{datetime: ~U[2026-06-24 14:30:00Z]}

      html =
        rendered_to_string(~H"""
        <.admin_local_time
          id="checkin-time-99"
          datetime={@datetime}
          class="whitespace-nowrap"
          phx-update="ignore"
        >
          Jun 24, 14:30 UTC
        </.admin_local_time>
        """)

      assert html =~ ~s(id="checkin-time-99")
      assert html =~ "whitespace-nowrap"
      assert html =~ ~s(phx-update="ignore")
      assert html =~ "Jun 24, 14:30 UTC"
    end

    test "forwards data-prefix for scheduled fallback copy" do
      assigns = %{datetime: ~U[2026-10-12 21:15:00Z]}

      html =
        rendered_to_string(~H"""
        <.admin_local_time
          id="job-time-7-scheduled"
          datetime={@datetime}
          data-prefix="Scheduled: "
        >
          Scheduled: 2026-10-12 21:15:00 UTC
        </.admin_local_time>
        """)

      assert html =~ ~s(data-prefix="Scheduled: ")
      assert html =~ ~s(data-utc-time="2026-10-12T21:15:00Z")
      assert html =~ "Scheduled: 2026-10-12 21:15:00 UTC"
    end
  end
end
