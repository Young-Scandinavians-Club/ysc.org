defmodule YscWeb.Components.LoadingSpinnerTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "loading_spinner/1" do
    test "renders a decorative ring spinner with the required id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.loading_spinner id="delete-pm-spinner" />
        """)

      assert html =~ ~s(id="delete-pm-spinner")
      assert html =~ "animate-spin"
      assert html =~ ~s(aria-hidden="true")
      assert html =~ ~s(viewBox="0 0 24 24")
      assert html =~ "w-5 h-5"
    end

    test "merges size and color classes onto the svg" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.loading_spinner
          id="avatar-processing-overlay-spinner"
          class="w-8 h-8 text-blue-600"
        />
        """)

      assert html =~ ~s(id="avatar-processing-overlay-spinner")
      assert html =~ "w-8 h-8"
      assert html =~ "text-blue-600"
      assert html =~ "animate-spin"
    end
  end
end
