defmodule YscWeb.AdminMobileListTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  describe "admin_mobile_list/1" do
    test "renders a mobile-only stacked list with the given id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_mobile_list id="admin-posts-mobile">
          <p>Card body</p>
        </.admin_mobile_list>
        """)

      assert html =~ ~s(id="admin-posts-mobile")
      assert html =~ "block md:hidden space-y-4"
      assert html =~ "Card body"
    end

    test "merges extra classes onto the wrapper" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_mobile_list id="admin-extra" class="pt-2">
          Extra
        </.admin_mobile_list>
        """)

      assert html =~ "pt-2"
      assert html =~ "block md:hidden space-y-4"
    end
  end

  describe "admin_mobile_list_card/1" do
    test "renders interactive card chrome by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_mobile_list_card id="admin-post-card-1">
          Title
        </.admin_mobile_list_card>
        """)

      assert html =~ ~s(id="admin-post-card-1")
      assert html =~ "bg-white rounded-lg border border-zinc-200 p-4"
      assert html =~ "hover:shadow-md"
      assert html =~ "Title"
      refute html =~ "cursor-pointer"
      refute html =~ "border-t border-zinc-200"
    end

    test "omits hover shadow when interactive is false" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_mobile_list_card id="static-card" interactive={false}>
          Static
        </.admin_mobile_list_card>
        """)

      refute html =~ "hover:shadow-md"
      assert html =~ "Static"
    end

    test "adds pointer cursor when clickable" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_mobile_list_card id="click-card" clickable phx-click="open">
          Click
        </.admin_mobile_list_card>
        """)

      assert html =~ "cursor-pointer"
      assert html =~ "phx-click"
      assert html =~ "open"
    end

    test "renders an end-aligned footer by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_mobile_list_card id="footer-card">
          Body
          <:footer>
            <button type="button">Actions</button>
          </:footer>
        </.admin_mobile_list_card>
        """)

      assert html =~ "justify-end"
      refute html =~ "justify-between"
      assert html =~ "border-t border-zinc-200"
      assert html =~ "Actions"
    end

    test "renders a between-aligned footer for badge plus actions" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_mobile_list_card id="between-card" footer_align={:between}>
          Body
          <:footer>
            <span>Badge</span>
            <button type="button">Actions</button>
          </:footer>
        </.admin_mobile_list_card>
        """)

      assert html =~ "justify-between"
      assert html =~ "Badge"
      assert html =~ "Actions"
    end
  end
end
