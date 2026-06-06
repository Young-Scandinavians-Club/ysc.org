defmodule YscWeb.AdminFilterDropdownTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  import Phoenix.LiveViewTest
  import YscWeb.AdminComponents

  defp sample_meta do
    %Flop.Meta{
      errors: [],
      has_next_page?: false,
      has_previous_page?: false,
      current_page: 1,
      total_pages: 1,
      previous_page: nil,
      next_page: nil,
      flop: %Flop{page: 1, page_size: 10}
    }
  end

  describe "admin_filter_dropdown/1" do
    test "renders funnel trigger, filter slot, and clear-filters button" do
      assigns = %{meta: sample_meta()}

      html =
        rendered_to_string(~H"""
        <.admin_filter_dropdown
          id="filter-test-dropdown"
          clear_patch="/admin/items"
          clear_id="admin-items-clear-filters"
        >
          <.filter_form fields={[]} meta={@meta} id="items-filter-form" />
        </.admin_filter_dropdown>
        """)

      assert html =~ "filter-test-dropdown"
      assert html =~ "filter-test-dropdownLink"
      assert html =~ "hero-funnel"
      assert html =~ "Filters"
      assert html =~ "items-filter-form"
      assert html =~ ~s(id="admin-items-clear-filters")
      assert html =~ "Clear filters"
      assert html =~ "hero-x-circle"
    end

    test "passes wide attribute through to dropdown panel" do
      assigns = %{meta: sample_meta()}

      html =
        rendered_to_string(~H"""
        <.admin_filter_dropdown
          id="filter-wide-dropdown"
          clear_patch="/admin/items"
          wide
        >
          <.filter_form fields={[]} meta={@meta} id="wide-filter-form" />
        </.admin_filter_dropdown>
        """)

      assert html =~ "wide"
    end
  end
end
