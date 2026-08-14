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

  describe "newsletter_edition_status_badge_type/1" do
    test "maps known edition statuses to badge types" do
      assert newsletter_edition_status_badge_type(:draft) == "yellow"
      assert newsletter_edition_status_badge_type(:scheduled) == "sky"
      assert newsletter_edition_status_badge_type(:sent) == "green"
      assert newsletter_edition_status_badge_type(:archived) == "dark"
    end
  end

  describe "newsletter_edition_status_label/1" do
    test "maps known edition statuses to labels" do
      assert newsletter_edition_status_label(:draft) == "Draft"
      assert newsletter_edition_status_label(:scheduled) == "Scheduled"
      assert newsletter_edition_status_label(:sent) == "Sent"
    end

    test "capitalizes unknown statuses" do
      assert newsletter_edition_status_label(:archived) == "Archived"
    end
  end

  describe "newsletter_subscriber_status_badge_type/1" do
    test "maps subscribed flag to badge types" do
      assert newsletter_subscriber_status_badge_type(true) == "green"
      assert newsletter_subscriber_status_badge_type(false) == "zinc"
    end
  end

  describe "newsletter_subscriber_status_label/1" do
    test "maps subscribed flag to labels" do
      assert newsletter_subscriber_status_label(true) == "Active"
      assert newsletter_subscriber_status_label(false) == "Inactive"
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
      assert format_quickbooks_sync_error(%{
               "Fault" => %{"Error" => [%{"Message" => "x"}]}
             }) =~
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
      assert html =~ "items-start"
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

  describe "admin_magic_search_section/1 and admin_magic_search_link/1" do
    test "renders section title and link row when show? is true" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_magic_search_section title="Events" show?={true}>
          <.admin_magic_search_link navigate="/admin/events/1/edit">
            <div class="font-medium">Summer Gala</div>
          </.admin_magic_search_link>
        </.admin_magic_search_section>
        """)

      assert html =~ "Events"
      assert html =~ "Summer Gala"
      assert html =~ ~s(data-phx-link="redirect")
      assert html =~ "/admin/events/1/edit"
      assert html =~ "data-result-item"
    end

    test "renders nothing when show? is false" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_magic_search_section title="Events" show?={false}>
          <.admin_magic_search_link navigate="/admin/events/1/edit">
            <div class="font-medium">Summer Gala</div>
          </.admin_magic_search_link>
        </.admin_magic_search_section>
        """)

      refute html =~ "Summer Gala"
      refute html =~ "Events"
    end
  end

  describe "admin_list_empty_state/1" do
    test "renders viking empty state with title and suggestion" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_list_empty_state
          title="No results found"
          suggestion="Try adjusting your search term and filters."
        />
        """)

      assert html =~ "No results found"
      assert html =~ "Try adjusting your search term and filters."
      assert html =~ "viking_4.png"
      refute html =~ "Clear filters"
    end

    test "renders patch-based clear filters button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_list_empty_state
          title="No results found"
          clear_id="clear-empty"
          clear_patch="/admin/users"
        />
        """)

      assert html =~ ~s(id="clear-empty")
      assert html =~ "Clear filters"
      assert html =~ ~s(data-phx-link="patch")
      assert html =~ "/admin/users"
    end

    test "renders event-based clear filters button" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_list_empty_state
          title="No reservations found"
          clear_event="clear-reservation-filters"
        />
        """)

      assert html =~ ~s(phx-click="clear-reservation-filters")
      assert html =~ "Clear filters"
      refute html =~ ~s(data-phx-link="patch")
    end
  end

  describe "admin_prev_next_pagination/1" do
    test "renders page summary and navigation buttons" do
      html =
        Phoenix.LiveViewTest.render_component(
          &admin_prev_next_pagination/1,
          %{
            page: 2,
            entry_count: 15,
            prev_event: "items_prev-page",
            next_event: "items_next-page",
            prev_disabled?: false,
            next_disabled?: false
          }
        )

      assert html =~ "Page 2"
      assert html =~ "Showing 15 entries"
      assert html =~ ~s(phx-click="items_prev-page")
      assert html =~ ~s(phx-click="items_next-page")
      assert html =~ "Previous"
      assert html =~ "Next"
    end

    test "disables previous button on first page" do
      html =
        Phoenix.LiveViewTest.render_component(
          &admin_prev_next_pagination/1,
          %{
            page: 1,
            entry_count: 0,
            prev_event: "items_prev-page",
            next_event: "items_next-page",
            prev_disabled?: true,
            next_disabled?: true
          }
        )

      assert html =~ "disabled"
      assert html =~ "bg-zinc-300"
      refute html =~ "bg-blue-600 hover:bg-blue-700"
    end

    test "uses active button styles when navigation is enabled" do
      html =
        Phoenix.LiveViewTest.render_component(
          &admin_prev_next_pagination/1,
          %{
            page: 3,
            entry_count: 25,
            prev_event: "items_prev-page",
            next_event: "items_next-page",
            prev_disabled?: false,
            next_disabled?: false
          }
        )

      assert html =~ "bg-blue-600 hover:bg-blue-700"
      refute html =~ "bg-zinc-300 text-zinc-500 cursor-not-allowed opacity-50"
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

  describe "admin_grant_entitlement_fields/1" do
    test "renders benefit type radios and default percent_off fields" do
      form =
        Phoenix.Component.to_form(
          %{
            "benefit_kind" => "percent_off",
            "property" => "",
            "expires_on" => "",
            "percent_off" => "",
            "buyout_max_discount" => "",
            "internal_note" => ""
          },
          as: :entitlement
        )

      html =
        Phoenix.LiveViewTest.render_component(
          &admin_grant_entitlement_fields/1,
          %{form: form}
        )

      assert html =~ "Benefit type"
      assert html =~ "Percent off stay"
      assert html =~ "Percent off (e.g. 50)"
      assert html =~ "Buyout max discount (USD)"
      assert html =~ "Internal note (optional)"
      refute html =~ "Free nights count"
    end

    test "renders free nights fields when benefit kind is free_nights" do
      form =
        Phoenix.Component.to_form(
          %{
            "benefit_kind" => "free_nights",
            "property" => "",
            "expires_on" => "",
            "free_nights" => "",
            "max_guests" => "",
            "internal_note" => ""
          },
          as: :entitlement
        )

      html =
        Phoenix.LiveViewTest.render_component(
          &admin_grant_entitlement_fields/1,
          %{form: form}
        )

      assert html =~ "Free nights count"
      assert html =~ "Max guests (optional)"
      refute html =~ "Buyout max discount (USD)"
    end
  end

  describe "admin_table_message/1" do
    test "renders centered table status text with optional id" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_table_message id="entitlements-loading">
          Loading entitlements…
        </.admin_table_message>
        """)

      assert html =~ ~s(id="entitlements-loading")
      assert html =~ "Loading entitlements…"
      assert html =~ "px-4 py-8 text-center text-zinc-500 text-sm"
    end
  end

  describe "admin_clipboard_button/1" do
    test "icon variant renders compact clipboard control" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_clipboard_button
          id="copy-payment-ref-123"
          variant={:icon}
          copy="PAY-123"
          title="Copy reference ID"
          aria_label="Copy reference ID"
        />
        """)

      assert html =~ ~s(id="copy-payment-ref-123")
      assert html =~ ~s(phx-hook="ClipboardCopy")
      assert html =~ ~s(data-copy="PAY-123")
      assert html =~ ~s(aria-label="Copy reference ID")
      assert html =~ "hero-clipboard"
      assert html =~ "w-4 h-4"
    end

    test "labeled_feedback variant renders label and feedback element" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_clipboard_button
          id="copy-path-btn"
          variant={:labeled_feedback}
          copy_target="image-path-text-original"
          icon="hero-link"
          label="Copy URL"
          title="Copy URL to clipboard"
        />
        """)

      assert html =~ ~s(id="copy-path-btn")
      assert html =~ "Copy URL"
      assert html =~ "hero-link"
      assert html =~ ~s(data-copy-target="image-path-text-original")
      assert html =~ ~s(data-copy-feedback="copy-path-btn-feedback")
      assert html =~ ~s(id="copy-path-btn-feedback")
      assert html =~ "data-copy-feedback-label"
    end
  end

  describe "admin_readonly_copy_field/1" do
    test "renders readonly input and copy button with shared value" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_readonly_copy_field
          id="share-url-input"
          copy_button_id="copy-share-url-btn"
          value="https://ysc.org/events/abc/photos"
        />
        """)

      assert html =~ ~s(id="share-url-input")
      assert html =~ ~s(readonly)
      assert html =~ ~s(value="https://ysc.org/events/abc/photos")
      assert html =~ ~s(id="copy-share-url-btn")
      assert html =~ ~s(phx-hook="ClipboardCopy")
      assert html =~ ~s(data-copy="https://ysc.org/events/abc/photos")
      assert html =~ "Copy link"
      assert html =~ "hero-clipboard"
    end

    test "supports custom label and input classes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_readonly_copy_field
          id="custom-input"
          copy_button_id="custom-copy-btn"
          value="https://example.com"
          label="Copy URL"
          input_class="flex-1 font-mono text-xs"
        />
        """)

      assert html =~ "Copy URL"
      assert html =~ "font-mono text-xs"
    end
  end

  describe "admin_volunteer_help_banner/1" do
    test "renders interactive help link by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_volunteer_help_banner />
        """)

      assert html =~ ~s(id="volunteer-help-banner")
      assert html =~ "Volunteer guides"
      assert html =~ ~s(href="/admin/help")
      assert html =~ "Open Help"
    end

    test "renders non-interactive stub for ghost previews" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.admin_volunteer_help_banner interactive?={false} />
        """)

      assert html =~ "Volunteer guides"
      assert html =~ "Open Help"
      refute html =~ ~s(href="/admin/help")
    end
  end
end
