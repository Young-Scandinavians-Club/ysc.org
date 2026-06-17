defmodule YscWeb.Components.PageMastheadTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "page_masthead/1" do
    test "renders default size with eyebrow and h1 title" do
      assigns = %{}

      heex = ~H"""
      <.page_masthead id="events-masthead" eyebrow="Events" title="What's Next" />
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="events-masthead"|
      assert html =~ "border-y border-zinc-200"
      assert html =~ "py-8 md:py-12"
      assert html =~ "Events"
      assert html =~ "What's Next"
      assert html =~ "text-4xl md:text-7xl"
      assert html =~ "<h1"
      refute html =~ "<h2"
    end

    test "renders large size with subtitle" do
      assigns = %{}

      heex = ~H"""
      <.page_masthead
        size={:large}
        title="Newsletters"
        subtitle="Browse our past newsletters."
      />
      """

      html = rendered_to_string(heex)

      assert html =~ "py-12"
      assert html =~ "text-6xl md:text-8xl"
      assert html =~ "tracking-tighter"
      assert html =~ "Browse our past newsletters."
      refute html =~ "py-8 md:py-12"
    end

    test "renders h2 heading and merges title_class" do
      assigns = %{}

      heex = ~H"""
      <.page_masthead
        eyebrow="Since 1993"
        title="Experience Tahoe"
        heading_tag={:h2}
        title_class="tracking-tighter"
      />
      """

      html = rendered_to_string(heex)

      assert html =~ "<h2"
      assert html =~ "Experience Tahoe"
      assert html =~ "tracking-tighter"
      refute html =~ "<h1"
    end

    test "renders inner block content below the title" do
      assigns = %{}

      heex = ~H"""
      <.page_masthead eyebrow="History" title="75+ Years">
        <p class="history-serif">Established 1950</p>
      </.page_masthead>
      """

      html = rendered_to_string(heex)

      assert html =~ "Established 1950"
      assert html =~ "history-serif"
    end
  end

  describe "feature_card/1" do
    test "renders muted feature card with body slot" do
      assigns = %{}

      heex = ~H"""
      <.feature_card title="Private Dock Access">
        <p>Swim, boat, and unwind.</p>
      </.feature_card>
      """

      html = rendered_to_string(heex)

      assert html =~ "bg-zinc-50"
      assert html =~ "border-zinc-100"
      assert html =~ "Private Dock Access"
      assert html =~ "text-zinc-500"
      assert html =~ "Swim, boat, and unwind."
    end

    test "renders accent feature card styling" do
      assigns = %{}

      heex = ~H"""
      <.feature_card title="Ready to Book?" title_tone={:accent} class="text-center">
        <p>Sign in to view availability.</p>
      </.feature_card>
      """

      html = rendered_to_string(heex)

      assert html =~ "bg-blue-50/40"
      assert html =~ "border-blue-200"
      assert html =~ "text-blue-600"
      assert html =~ "text-center"
      assert html =~ "Sign in to view availability."
    end
  end
end
