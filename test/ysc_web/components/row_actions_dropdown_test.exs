defmodule YscWeb.RowActionsDropdownTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "row_actions_dropdown/1" do
    test "renders ellipsis trigger and menu container" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.row_actions_dropdown id="row-actions-1" label="Event actions">
          <.dropdown_menu_item id="row-actions-1-edit" icon="hero-pencil-square">
            Edit
          </.dropdown_menu_item>
        </.row_actions_dropdown>
        """)

      assert html =~ ~s(id="row-actions-1")
      assert html =~ "hero-ellipsis-vertical"
      assert html =~ "Event actions"
      assert html =~ ~s(id="row-actions-1-edit")
      assert html =~ "Edit"
      assert html =~ "hero-pencil-square"
      # Click propagation is stopped via a CSP-safe hook, not an inline handler.
      refute html =~ "onclick"
      assert html =~ ~s(phx-hook="StopClick")
      assert html =~ ~s(id="row-actions-1-stop-click")
      assert html =~ "bottom-full mb-1"
      refute html =~ ~r/\bmt-1\b/
    end
  end

  describe "dropdown_menu_item/1" do
    test "renders a navigate link with default tone" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.row_actions_dropdown id="menu-1" label="Actions">
          <.dropdown_menu_item
            id="menu-1-edit"
            icon="hero-pencil-square"
            navigate="/admin/items/1"
          >
            Edit
          </.dropdown_menu_item>
        </.row_actions_dropdown>
        """)

      assert html =~ ~s(href="/admin/items/1")
      assert html =~ "text-zinc-500"
      refute html =~ "text-emerald-700"
    end

    test "renders a button with success tone" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.row_actions_dropdown id="menu-2" label="Actions">
          <.dropdown_menu_item
            id="menu-2-check-in"
            icon="hero-qr-code"
            tone={:success}
            phx-click="check-in"
          >
            Check in
          </.dropdown_menu_item>
        </.row_actions_dropdown>
        """)

      assert html =~ ~s(phx-click="check-in")
      assert html =~ "text-emerald-700"
      assert html =~ "Check in"
    end

    test "renders a static status row with custom leading content" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.row_actions_dropdown id="menu-3" label="Actions">
          <.dropdown_menu_item id="menu-3-sending" static tone={:info}>
            <:leading>
              <span class="spinner-test"></span>
            </:leading>
            Sending…
          </.dropdown_menu_item>
        </.row_actions_dropdown>
        """)

      assert html =~ "spinner-test"
      assert html =~ "text-blue-600"
      assert html =~ "Sending…"
      assert html =~ ~s(id="menu-3-sending")
      assert html =~ ~s(<span id="menu-3-sending")
    end

    test "renders danger tone and data-confirm on buttons" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.row_actions_dropdown id="menu-4" label="Actions">
          <.dropdown_menu_item
            id="menu-4-delete"
            icon="hero-trash"
            tone={:danger}
            phx-click="delete-item"
            data-confirm="Delete this item?"
          >
            Delete
          </.dropdown_menu_item>
        </.row_actions_dropdown>
        """)

      assert html =~ "text-red-600"
      assert html =~ ~s(data-confirm="Delete this item?")
      assert html =~ "hero-trash"
    end
  end
end
