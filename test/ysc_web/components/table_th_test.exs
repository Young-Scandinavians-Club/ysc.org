defmodule YscWeb.Components.TableThTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "table_th/1" do
    test "renders a left-aligned comfortable header by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <table>
          <thead>
            <tr>
              <.table_th>Category</.table_th>
            </tr>
          </thead>
        </table>
        """)

      assert html =~ "Category"
      assert html =~ ~s(scope="col")
      assert html =~ "type-eyebrow"
      assert html =~ "text-xs text-zinc-500"
      assert html =~ "px-6 py-3"
      assert html =~ "text-left"
      refute html =~ "text-right"
      refute html =~ "text-center"
    end

    test "supports right alignment and medium density" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <table>
          <thead>
            <tr>
              <.table_th align={:right} density={:medium}>Actions</.table_th>
            </tr>
          </thead>
        </table>
        """)

      assert html =~ "Actions"
      assert html =~ "text-right"
      assert html =~ "px-4 py-3"
      refute html =~ "px-6 py-3"
    end

    test "supports center alignment for status columns" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <table>
          <thead>
            <tr>
              <.table_th align={:center}>Status</.table_th>
            </tr>
          </thead>
        </table>
        """)

      assert html =~ "Status"
      assert html =~ "text-center"
      refute html =~ "text-left"
    end

    test "merges extra classes onto the header cell" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <table>
          <thead>
            <tr>
              <.table_th class="whitespace-nowrap">Member</.table_th>
            </tr>
          </thead>
        </table>
        """)

      assert html =~ "whitespace-nowrap"
      assert html =~ "type-eyebrow"
    end
  end
end
