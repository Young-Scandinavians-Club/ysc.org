defmodule YscWeb.AdminStatCardTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_stat_card/1" do
    test "renders label, value, and subtitle" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_stat_card
          label="Total Memberships"
          value={128}
          subtitle="Active primary accounts"
        />
        """)

      assert html =~ "Total Memberships"
      assert html =~ "128"
      assert html =~ "Active primary accounts"
      assert html =~ "tracking-[0.2em]"
      assert html =~ "text-3xl font-black text-zinc-900"
    end

    test "omits subtitle paragraph when not provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_stat_card label="Pending" value={3} />
        """)

      assert html =~ "Pending"
      assert html =~ "3"
      refute html =~ "text-xs text-zinc-500 mt-1 font-medium"
    end
  end
end
