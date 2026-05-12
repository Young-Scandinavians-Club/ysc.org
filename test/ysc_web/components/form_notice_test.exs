defmodule YscWeb.Components.FormNoticeTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "form_notice/1" do
    test "renders info with default icon, id, and bottom margin" do
      assigns = %{}

      heex = ~H"""
      <.form_notice kind={:info} id="notice-info">
        Body text
      </.form_notice>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="notice-info"|
      assert html =~ "bg-blue-50"
      assert html =~ "border-blue-200"
      assert html =~ "text-blue-800"
      assert html =~ "hero-information-circle"
      assert html =~ "Body text"
      assert html =~ "mb-4"
    end

    test "renders error without icon by default" do
      assigns = %{}

      heex = ~H"""
      <.form_notice kind={:error} id="notice-err">
        Something went wrong
      </.form_notice>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="notice-err"|
      assert html =~ "bg-red-50"
      assert html =~ "text-red-800"
      assert html =~ "Something went wrong"
      refute html =~ "hero-information-circle"
    end

    test "omits icon when icon is false" do
      assigns = %{}

      heex = ~H"""
      <.form_notice kind={:info} id="notice-plain" icon={false}>
        No icon
      </.form_notice>
      """

      html = rendered_to_string(heex)

      refute html =~ "hero-information-circle"
      assert html =~ "No icon"
    end

    test "uses custom icon when provided" do
      assigns = %{}

      heex = ~H"""
      <.form_notice kind={:error} id="notice-custom" icon="hero-exclamation-triangle">
        Bad
      </.form_notice>
      """

      html = rendered_to_string(heex)

      assert html =~ "hero-exclamation-triangle"
    end

    test "omits bottom margin when margin_bottom is false" do
      assigns = %{}

      heex = ~H"""
      <.form_notice kind={:error} id="notice-tight" margin_bottom={false}>
        x
      </.form_notice>
      """

      html = rendered_to_string(heex)

      refute html =~ "mb-4"
    end
  end
end
