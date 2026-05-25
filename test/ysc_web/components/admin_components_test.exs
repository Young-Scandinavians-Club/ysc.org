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

  describe "quickbooks_sync_status_badge_type/1" do
    test "maps known sync statuses to badge types" do
      assert quickbooks_sync_status_badge_type("pending") == "yellow"
      assert quickbooks_sync_status_badge_type("synced") == "green"
      assert quickbooks_sync_status_badge_type("failed") == "red"
      assert quickbooks_sync_status_badge_type("processing") == "default"
      assert quickbooks_sync_status_badge_type(nil) == "dark"
    end
  end

  describe "format_quickbooks_sync_error/1" do
    test "returns empty string for nil" do
      assert format_quickbooks_sync_error(nil) == ""
    end

    test "pretty-prints map errors as JSON" do
      assert format_quickbooks_sync_error(%{"Fault" => %{"Error" => [%{"Message" => "x"}]}}) =~
               "Fault"
    end
  end

  describe "admin_quickbooks_sync_status/1" do
    test "inline layout renders badge only" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_quickbooks_sync_status status="synced" layout={:inline} />
        """)

      assert html =~ "Synced"
      refute html =~ "cursor-help"
    end

    test "stack layout renders error label hint when error_hint is label" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_quickbooks_sync_status
          status="failed"
          error={%{"message" => "timeout"}}
          error_hint={:label}
        />
        """)

      assert html =~ "Failed"
      assert html =~ "Error"
      assert html =~ "timeout"
    end

    test "stack layout truncates error text when error_hint is truncate" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_quickbooks_sync_status
          status="pending"
          error="Connection refused"
          default_label="unknown"
        />
        """)

      assert html =~ "Pending"
      assert html =~ "Connection refused"
      assert html =~ "truncate"
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
