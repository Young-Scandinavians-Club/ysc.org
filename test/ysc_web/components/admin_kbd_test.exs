defmodule YscWeb.AdminKbdTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_kbd/1" do
    test "compact default includes shared shortcut hint styling" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_kbd size={:compact}>↑</.admin_kbd>
        """)

      assert html =~ ~s(<kbd class=")
      assert html =~ "min-w-[1.375rem]"
      assert html =~ "text-zinc-500"
      assert html =~ "↑"
    end

    test "inline size uses wider horizontal padding without min-width" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_kbd size={:inline}>↵ enter</.admin_kbd>
        """)

      assert html =~ "px-1.5 py-0.5"
      refute html =~ "min-w-[1.375rem]"
      assert html =~ "↵ enter"
    end

    test "muted tone uses zinc-400 text" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_kbd size={:compact} tone={:muted}>1</.admin_kbd>
        """)

      assert html =~ "text-zinc-400"
      refute html =~ "text-zinc-500"
    end

    test "forwards data-key onto the kbd element" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_kbd size={:inline} data-key="alt">alt</.admin_kbd>
        """)

      assert html =~ ~s(data-key="alt")
    end

    test "merges optional class onto the key" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_kbd size={:compact} class="ring-1 ring-zinc-200">x</.admin_kbd>
        """)

      assert html =~ "ring-1 ring-zinc-200"
    end
  end
end
