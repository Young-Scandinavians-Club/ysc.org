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

    test "renders success with default check icon and alert role" do
      assigns = %{}

      heex = ~H"""
      <.form_notice kind={:success} id="notice-ok">
        All set
      </.form_notice>
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="notice-ok"|
      assert html =~ ~s|role="alert"|
      assert html =~ "bg-green-50"
      assert html =~ "border-green-200"
      assert html =~ "text-green-800"
      assert html =~ "hero-check-circle"
      assert html =~ "All set"
    end

    test "renders comfortable size with larger padding and rounded-lg" do
      assigns = %{}

      heex = ~H"""
      <.form_notice kind={:error} id="notice-large" size={:comfortable}>
        Big box
      </.form_notice>
      """

      html = rendered_to_string(heex)

      assert html =~ "p-4"
      assert html =~ "mb-6"
      assert html =~ "rounded-lg"
      refute html =~ "rounded-md"
    end

    test "merges extra class onto the wrapper" do
      assigns = %{}

      heex = ~H"""
      <.form_notice kind={:success} id="notice-extra" class="not-prose">
        Styled
      </.form_notice>
      """

      html = rendered_to_string(heex)

      assert html =~ "not-prose"
    end
  end
end
