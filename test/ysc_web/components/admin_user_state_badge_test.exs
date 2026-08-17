defmodule YscWeb.AdminUserStateBadgeTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_user_state_badge/1" do
    test "renders pending approval with yellow badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_user_state_badge state={:pending_approval} />
        """)

      assert html =~ "Pending Approval"
      assert html =~ "bg-yellow-100 text-yellow-800"
    end

    test "renders active with green badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_user_state_badge state={:active} />
        """)

      assert html =~ "Active"
      assert html =~ "bg-green-100 text-green-800"
    end

    test "renders rejected with red badge" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_user_state_badge state={:rejected} />
        """)

      assert html =~ "Rejected"
      assert html =~ "bg-red-100 text-red-800"
    end
  end
end
