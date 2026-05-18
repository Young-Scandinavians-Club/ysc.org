defmodule YscWeb.Components.AsyncSectionLoaderTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "async_section_loader/1" do
    test "renders centered spinner row with label and default padding" do
      assigns = %{}

      heex = ~H"""
      <.async_section_loader id="loader-test" label="Loading widgets..." />
      """

      html = rendered_to_string(heex)

      assert html =~ ~s|id="loader-test"|
      assert html =~ "flex items-center justify-center"
      assert html =~ "py-8"
      assert html =~ "hero-arrow-path"
      assert html =~ "animate-spin"
      assert html =~ "Loading widgets..."
    end

    test "merges custom class for vertical padding" do
      assigns = %{}

      heex = ~H"""
      <.async_section_loader label="Wait…" class="py-12" />
      """

      html = rendered_to_string(heex)

      assert html =~ "py-12"
      assert html =~ "Wait…"
    end
  end
end
