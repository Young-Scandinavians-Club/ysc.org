defmodule YscWeb.AdminComponentsTest do
  use YscWeb.ConnCase, async: true
  use Phoenix.Component

  require Phoenix.LiveViewTest

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import YscWeb.AdminComponents

  defp sample_meta do
    %Flop.Meta{
      errors: [],
      has_next_page?: true,
      has_previous_page?: true,
      current_page: 2,
      total_pages: 5,
      previous_page: 1,
      next_page: 3,
      flop: %Flop{page: 2, page_size: 10}
    }
  end

  defp render_pagination(opts) do
    assigns =
      %{meta: sample_meta(), path: "/admin/items", density: :comfortable}
      |> Map.merge(Map.new(opts))

    Phoenix.LiveViewTest.render_component(
      &admin_flop_pagination/1,
      assigns
    )
  end

  describe "admin_flop_pagination/1" do
    test "renders nothing when meta is nil" do
      html =
        Phoenix.LiveViewTest.render_component(
          &admin_flop_pagination/1,
          %{
            meta: nil,
            path: "/admin/items",
            density: :comfortable
          }
        )

      refute html =~ "hero-chevron-left"
    end

    test "compact density uses tighter vertical padding class" do
      html = render_pagination(%{density: :compact})
      assert html =~ "py-4"
      refute html =~ "py-10"
    end

    test "comfortable density uses roomier vertical padding class" do
      html = render_pagination(%{density: :comfortable})
      assert html =~ "py-10"
      refute html =~ "py-4"
    end

    test "includes navigation icons" do
      html = render_pagination(%{})
      assert html =~ "hero-chevron-left"
      assert html =~ "hero-chevron-right"
    end
  end

  describe "admin_dashed_more_button/1" do
    test "renders a dashed full-width button with label and phx-click" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_dashed_more_button phx-click="show-more">
          Load more
        </.admin_dashed_more_button>
        """)

      assert html =~ ~s(phx-click="show-more")
      assert html =~ "Load more"
      assert html =~ "border-dashed"
      assert html =~ "type=\"button\""
    end

    test "merges optional class onto the button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_dashed_more_button class="mb-2">x</.admin_dashed_more_button>
        """)

      assert html =~ "mb-2"
    end
  end
end
