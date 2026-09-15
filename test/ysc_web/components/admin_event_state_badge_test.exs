defmodule YscWeb.AdminEventStateBadgeTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_event_state_badge/1" do
    test "renders draft with sky badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_state_badge id="event-state-draft" state={:draft} />
        """)

      assert html =~ ~s(id="event-state-draft")
      assert html =~ "Draft"
      assert html =~ "bg-sky-100 text-sky-800"
      refute html =~ "Publishes on"
    end

    test "renders published with green badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_state_badge state={:published} />
        """)

      assert html =~ "Published"
      assert html =~ "bg-green-100 text-green-800"
    end

    test "renders cancelled with dark zinc badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_state_badge state={:cancelled} />
        """)

      assert html =~ "Cancelled"
      assert html =~ "bg-zinc-100 text-zinc-800"
    end

    test "renders deleted with red badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_state_badge state={:deleted} />
        """)

      assert html =~ "Deleted"
      assert html =~ "bg-red-100 text-red-800"
    end

    test "scheduled without publish_at has no tooltip" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_event_state_badge state={:scheduled} />
        """)

      assert html =~ "Scheduled"
      assert html =~ "bg-yellow-100 text-yellow-800"
      refute html =~ "Publishes on"
    end

    test "scheduled with publish_at shows Pacific tooltip" do
      publish_at = DateTime.from_naive!(~N[2026-06-15 19:30:00], "Etc/UTC")
      assigns = %{publish_at: publish_at}

      html =
        rendered_to_string(~H"""
        <.admin_event_state_badge state={:scheduled} publish_at={@publish_at} />
        """)

      assert html =~ "Scheduled"
      assert html =~ "bg-yellow-100 text-yellow-800"
      assert html =~ "Publishes on June 15, 2026 at 12:30 PM"
    end
  end
end
