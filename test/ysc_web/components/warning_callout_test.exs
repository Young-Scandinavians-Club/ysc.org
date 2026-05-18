defmodule YscWeb.Components.WarningCalloutTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.HTML
  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "warning_callout/1" do
    test "renders amber panel with icon, title, and body" do
      assigns = %{}

      heex = ~H"""
      <.warning_callout id="warn-1" title="Cannot book">
        {raw("<span>Please renew</span>")}
      </.warning_callout>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="warn-1"|
      assert html =~ "bg-amber-50"
      assert html =~ "border-amber-200"
      assert html =~ "hero-exclamation-triangle-solid"
      assert html =~ "Cannot book"
      assert html =~ "<span>Please renew</span>"
    end

    test "omits title heading when title is nil" do
      assigns = %{}

      heex = ~H"""
      <.warning_callout>
        Plain message
      </.warning_callout>
      """

      html = rendered_to_string(heex)

      refute html =~ "<h3"
      assert html =~ "Plain message"
    end

    test "merges optional class onto container" do
      assigns = %{}

      heex = ~H"""
      <.warning_callout class="shadow-md">
        x
      </.warning_callout>
      """

      html = rendered_to_string(heex)

      assert html =~ "shadow-md"
      assert html =~ "bg-amber-50"
    end
  end
end
