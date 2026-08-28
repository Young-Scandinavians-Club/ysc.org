defmodule YscWeb.PhoenixLiveViewUpgradeTest do
  @moduledoc """
  Guards the phoenix_live_view 1.2.10 → 1.2.11 upgrade.

  1.2.11 is a patch: stale pending diffs are discarded on rejoin, removed
  LiveComponents cancel in-flight `start_async`/`assign_async` tasks, and
  the HTMLFormatter no longer migrates EEx expressions that would close
  curly interpolation early. No Elixir API breaks.
  """
  use ExUnit.Case, async: true

  @live_view_js Path.expand(
                  "../../deps/phoenix_live_view/priv/static/phoenix_live_view.js",
                  __DIR__
                )
  @channel_ex Path.expand(
                "../../deps/phoenix_live_view/lib/phoenix_live_view/channel.ex",
                __DIR__
              )
  @html_algebra_ex Path.expand(
                     "../../deps/phoenix_live_view/lib/phoenix_live_view/html_algebra.ex",
                     __DIR__
                   )
  @live_component_files [
    "lib/ysc_web/live/reauth_component.ex",
    "lib/ysc_web/components/uploader/upload_component.ex",
    "lib/ysc_web/components/uploader/file_component.ex",
    "lib/ysc_web/components/trix_image_picker_component.ex",
    "lib/ysc_web/components/news/news_list.ex",
    "lib/ysc_web/components/media_picker_component.ex",
    "lib/ysc_web/components/map_component.ex",
    "lib/ysc_web/components/image_upload_component.ex",
    "lib/ysc_web/components/image.ex",
    "lib/ysc_web/components/gallery_component.ex",
    "lib/ysc_web/components/agendas/admin_agenda_form.ex",
    "lib/ysc_web/components/events/user_events_list.ex",
    "lib/ysc_web/components/agendas/admin_agenda_edit.ex",
    "lib/ysc_web/components/events/ticket_tier_management.ex",
    "lib/ysc_web/components/admin_search.ex",
    "lib/ysc_web/components/events/ticket_tier_form.ex",
    "lib/ysc_web/components/events/ticket_reservation_form.ex",
    "lib/ysc_web/components/events/admin_schedule_form.ex",
    "lib/ysc_web/components/events/ticket_list.ex",
    "lib/ysc_web/components/date_range_picker.ex",
    "lib/ysc_web/components/events/ticket_grant_form.ex",
    "lib/ysc_web/components/events/event_list.ex",
    "lib/ysc_web/components/availability_calendar.ex",
    "lib/ysc_web/components/live_phone.ex"
  ]

  describe "1.2.11 Hex lock and public APIs" do
    test "locks the Hex package to 1.2.11" do
      assert to_string(Application.spec(:phoenix_live_view, :vsn)) == "1.2.11"
    end

    test "start_async, assign_async, and cancel_async still exist" do
      assert macro_exported?(Phoenix.LiveView, :start_async, 3)
      assert macro_exported?(Phoenix.LiveView, :start_async, 4)
      assert macro_exported?(Phoenix.LiveView, :assign_async, 3)
      assert macro_exported?(Phoenix.LiveView, :assign_async, 4)
      assert function_exported?(Phoenix.LiveView, :cancel_async, 2)
      assert function_exported?(Phoenix.LiveView, :cancel_async, 3)
    end

    test "LiveComponent and LiveViewTest modules we use still load" do
      assert {:module, Phoenix.LiveComponent} =
               Code.ensure_loaded(Phoenix.LiveComponent)

      assert {:module, Phoenix.LiveViewTest} =
               Code.ensure_loaded(Phoenix.LiveViewTest)

      assert {:module, Phoenix.LiveView.HTMLFormatter} =
               Code.ensure_loaded(Phoenix.LiveView.HTMLFormatter)

      assert {:module, Phoenix.LiveView.JS} =
               Code.ensure_loaded(Phoenix.LiveView.JS)
    end
  end

  describe "1.2.11 stale diffs on rejoin" do
    test "JS client tags pending diffs with joinCount and discards stale ones" do
      js = File.read!(@live_view_js)

      assert js =~
               "this.pendingDiffs.push({ diff, events, joinCount: this.joinCount })"

      assert js =~ "view.stale-diff-discarded"
      assert js =~ "discarded diff from previous join"
    end
  end

  describe "1.2.11 LiveComponent async cancellation" do
    test "delete_components cancels in-flight live_async tasks" do
      source = File.read!(@channel_ex)

      assert source =~ "cancel_asyncs(c_socket)"

      assert source =~
               "A removed component can no longer handle its async results, so we cancel any"

      assert source =~ "Async.cancel_async(c_socket, key, {:shutdown, :cancel})"
    end

    test "app LiveComponents do not start_async or assign_async" do
      # 1.2.11 cancels component asyncs when the cid is destroyed. We only
      # start_async from LiveViews, so removal of these components is a no-op
      # for that path. Guard against introducing component-owned asyncs
      # without tests that call render_async/2 before destroying the cid.
      Enum.each(@live_component_files, fn relative_path ->
        path = Path.expand("../../#{relative_path}", __DIR__)
        contents = File.read!(path)

        refute contents =~ "start_async(",
               "#{relative_path} must not call start_async/3; 1.2.11 cancels those on removal"

        refute contents =~ "assign_async(",
               "#{relative_path} must not call assign_async/3; 1.2.11 cancels those on removal"
      end)
    end
  end

  describe "1.2.11 HTMLFormatter early-close migration" do
    test "prefix-depth gate refuses to migrate expressions that close at depth 0" do
      source = File.read!(@html_algebra_ex)

      # The 1.2.10 gate only checked total brace balance. 1.2.11 also rejects
      # a `}` that would close interpolation at the first depth-0 prefix.
      assert source =~ ~s|defp safe_to_migrate?("}" <> _rest, 0), do: false|
    end

    test "leaves EEx that would close curly interpolation early unmigrated" do
      source = ~s|<p><%= "}" <> "{" %></p>\n|

      formatted = Phoenix.LiveView.HTMLFormatter.format(source, line_length: 80)

      assert formatted =~ "<%="
      refute formatted =~ ~s|{"}" <> "{"}|
    end

    test "still migrates balanced EEx interpolations to curly syntax" do
      source = ~s|<p><%= @title %></p>\n|

      formatted = Phoenix.LiveView.HTMLFormatter.format(source, line_length: 80)

      assert formatted =~ ~s|<p>{@title}</p>|
      refute formatted =~ "<%="
    end
  end
end
