defmodule YscWeb.AdminFlopLoadingStateTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_flop_loading_state/1" do
    test "renders spinner icon and message" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_flop_loading_state message="Loading events…" />
        """)

      assert html =~ "hero-arrow-path"
      assert html =~ "animate-spin"
      assert html =~ "Loading events…"
      assert html =~ "py-16 text-center"
    end

    test "merges extra classes onto the outer container" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_flop_loading_state message="Loading posts…" class="mt-8" />
        """)

      assert html =~ "mt-8"
      assert html =~ "Loading posts…"
    end
  end
end
