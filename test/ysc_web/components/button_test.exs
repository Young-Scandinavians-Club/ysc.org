defmodule YscWeb.CoreComponents.ButtonTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.CoreComponents

  describe "button/1" do
    test "uses phx-disable-with only as loading label (attribute is not rendered)" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.button phx-click="save" phx-disable-with="Saving...">Save</.button>
        """)

      refute html =~ "phx-disable-with"
      assert html =~ "Saving..."
      assert html =~ "phx-click=\"save\""
      assert html =~ "hero-arrow-path"
      assert html =~ "group-[.phx-click-loading]:hidden"
    end

    test "renders patch link markup when patch is set" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.button patch="/admin/scanner" loading_text="Opening...">Open</.button>
        """)

      assert html =~ "data-phx-link=\"patch\""
      assert html =~ ~s|href="/admin/scanner"|
      refute html =~ "<button"
    end

    test "omits spinner row for a static button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.button type="button">Dismiss</.button>
        """)

      refute html =~ "hero-arrow-path"
    end

    test "shows loading chrome for type=\"button\" with LiveView hooks" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.button type="button" phx-click="go" phx-disable-with="Working...">Go</.button>
        """)

      assert html =~ "Working..."
      assert html =~ "hero-arrow-path"
    end

    test "keeps phx-disable-with on the wire when structured loading is not used" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.button type="button" phx-disable-with="Nope...">Idle</.button>
        """)

      assert html =~ "phx-disable-with"
      refute html =~ "hero-arrow-path"
    end
  end
end
