defmodule YscWeb.Components.FormActionsTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "form_actions/1" do
    test "renders default modal spacing, id, and inner buttons" do
      assigns = %{}

      heex = ~H"""
      <.form_actions id="family-member-form-actions">
        <button type="button">Cancel</button>
        <button type="submit">Save</button>
      </.form_actions>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="family-member-form-actions"|
      assert html =~ "flex justify-end gap-3"
      assert html =~ "border-t border-zinc-200"
      assert html =~ "mt-8"
      assert html =~ "pt-4"
      refute html =~ "pt-6"
      assert html =~ "Cancel"
      assert html =~ "Save"
    end

    test "renders compact stacked-form spacing without extra top margin" do
      assigns = %{}

      heex = ~H"""
      <.form_actions id="ticket-grant-form-actions" spacing={:compact}>
        <button type="submit">Grant Tickets</button>
      </.form_actions>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="ticket-grant-form-actions"|
      assert html =~ "pt-6"
      refute html =~ "mt-8"
      refute html =~ "pt-4"
      assert html =~ "Grant Tickets"
    end

    test "merges extra class onto the wrapper" do
      assigns = %{}

      heex = ~H"""
      <.form_actions id="extra-actions" class="sm:px-2">
        <button type="submit">Go</button>
      </.form_actions>
      """

      html = rendered_to_string(heex)

      assert html =~ "sm:px-2"
      assert html =~ "Go"
    end
  end
end
