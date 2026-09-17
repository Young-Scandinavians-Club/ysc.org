defmodule YscWeb.PhoenixLiveViewUpgradeTest do
  @moduledoc """
  Guards the phoenix_live_view 1.2.11 → 1.2.12 upgrade.

  1.2.12 is a patch: hook `disconnected()` runs once; JS.push no longer
  mutates opts; `assign_async` validates keys with `Enum.any?/2` so falsy
  keys work; caret restore covers search/url/tel/password; LiveViewTest
  keyed move+change patches; portal teleport preserves namespace and
  clones the source; nested LiveView lock handling. No Elixir API breaks.
  """
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.JS

  @live_view_js Path.expand(
                  "../../deps/phoenix_live_view/priv/static/phoenix_live_view.js",
                  __DIR__
                )
  @async_ex Path.expand(
              "../../deps/phoenix_live_view/lib/phoenix_live_view/async.ex",
              __DIR__
            )
  @channel_ex Path.expand(
                "../../deps/phoenix_live_view/lib/phoenix_live_view/channel.ex",
                __DIR__
              )
  @test_diff_ex Path.expand(
                  "../../deps/phoenix_live_view/lib/phoenix_live_view/test/diff.ex",
                  __DIR__
                )
  @html_algebra_ex Path.expand(
                     "../../deps/phoenix_live_view/lib/phoenix_live_view/html_algebra.ex",
                     __DIR__
                   )
  @admin_search_ex Path.expand(
                     "../../lib/ysc_web/components/admin_search.ex",
                     __DIR__
                   )
  @live_phone_ex Path.expand(
                   "../../lib/ysc_web/components/live_phone.ex",
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

  describe "1.2.12 Hex lock and public APIs" do
    test "locks the Hex package to 1.2.12" do
      assert to_string(Application.spec(:phoenix_live_view, :vsn)) == "1.2.12"
    end

    test "start_async and assign_async macros still exist" do
      {:module, Phoenix.LiveView} = Code.ensure_loaded(Phoenix.LiveView)

      assert macro_exported?(Phoenix.LiveView, :start_async, 3)
      assert macro_exported?(Phoenix.LiveView, :start_async, 4)
      assert macro_exported?(Phoenix.LiveView, :assign_async, 3)
      assert macro_exported?(Phoenix.LiveView, :assign_async, 4)
      assert function_exported?(Phoenix.LiveView, :cancel_async, 2)
      assert function_exported?(Phoenix.LiveView, :cancel_async, 3)
    end

    test "JS.push arities we use still exist" do
      {:module, JS} = Code.ensure_loaded(JS)

      assert function_exported?(JS, :push, 1)
      assert function_exported?(JS, :push, 2)
      assert function_exported?(JS, :push, 3)
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

  describe "1.2.12 JS.push encoding and client opts" do
    test "encodes event, value, and LiveComponent target without dropping payload" do
      cid = %Phoenix.LiveComponent.CID{cid: 7}

      js =
        JS.push("delete", target: cid, value: %{id: "item-1"})
        |> JS.push("lv:clear-flash", value: %{key: :info})

      assert %JS{ops: ops} = js

      assert ["push", %{event: "delete", target: 7, value: %{id: "item-1"}}] in ops

      assert ["push", %{event: "lv:clear-flash", value: %{key: :info}}] in ops
    end

    test "rejects a non-map :value the same way as 1.2.11" do
      assert_raise ArgumentError, ~r/push :value expected to be a map/, fn ->
        JS.push("clicked", value: "not-a-map")
      end
    end

    test "JS client copies push opts instead of deleting opts.value" do
      js = File.read!(@live_view_js)

      assert js =~
               ~s|const _a = opts, { value } = _a, rest = __objRest(_a, ["value"])|

      assert js =~ "const data = value || {}"
      refute js =~ "delete opts.value"
    end
  end

  describe "1.2.12 hook disconnected runs once" do
    test "JS client only calls disconnected() when not already disconnected" do
      js = File.read!(@live_view_js)

      assert js =~ "if (!this.__isDisconnected) {"
      assert js =~ "this.__isDisconnected = true;"
      assert js =~ "this.disconnected();"
    end
  end

  describe "1.2.12 assign_async falsy keys" do
    test "missing-key check uses Enum.any? so false/0 keys are detected" do
      source = File.read!(@async_ex)

      assert source =~
               "if Enum.any?(keys, &(not is_map_key(assigns, &1))) do"

      refute source =~ "Enum.find(keys, &(not is_map_key(assigns, &1)))"
    end

    test "app LiveViews use start_async atoms, not assign_async" do
      # 1.2.12 only changes assign_async key validation. We start_async with
      # atom names like :load_home_data and never call assign_async.
      Enum.each(@live_component_files, fn relative_path ->
        path = Path.expand("../../#{relative_path}", __DIR__)
        contents = File.read!(path)

        refute contents =~ "assign_async(",
               "#{relative_path} must not call assign_async/3; we do not rely on that API"
      end)
    end
  end

  describe "1.2.12 caret restore for search and tel inputs" do
    test "JS client restores selection on search, url, tel, and password" do
      js = File.read!(@live_view_js)

      assert js =~
               ~s|["text", "textarea", "search", "url", "tel", "password"].includes(el.type)|
    end

    test "admin search and live phone still use search and tel input types" do
      assert File.read!(@admin_search_ex) =~ ~s|type="search"|
      assert File.read!(@live_phone_ex) =~ ~s|type="tel"|
    end
  end

  describe "1.2.12 LiveViewTest keyed move+change patches" do
    test "resolve_templates keeps [old_pos, diff] entries" do
      source = File.read!(@test_diff_ex)

      assert source =~
               "# a keyed entry that moved and changed is sent as [old_pos, diff]"

      assert source =~ "defp resolve_templates([old_pos, rendered], template)"
      assert source =~ "when is_integer(old_pos) and is_map(rendered) do"
    end
  end

  describe "1.2.12 portal teleport and nested LiveView locks" do
    test "JS client preserves namespace and clones teleported nodes" do
      js = File.read!(@live_view_js)

      assert js =~ "portalTarget = document.createElementNS("
      assert js =~ "morph(portalTarget, toTeleport.cloneNode(true), true);"
    end

    test "JS client ignores parent LiveView locks it does not own" do
      js = File.read!(@live_view_js)

      assert js =~ "view.ownsElement(closestLock)"
    end

    test "app does not live_render nested LiveViews or use portals" do
      lib_files =
        Path.wildcard(Path.expand("../../lib/**/*.{ex,heex}", __DIR__))

      Enum.each(lib_files, fn path ->
        contents = File.read!(path)

        refute contents =~ "live_render(",
               "#{Path.relative_to_cwd(path)} must not live_render nested LiveViews"

        refute contents =~ "Phoenix.Component.portal",
               "#{Path.relative_to_cwd(path)} must not use Phoenix.Component.portal"
      end)
    end
  end

  describe "1.2.12 async pid collection" do
    test "async_pids waits indefinitely instead of the default call timeout" do
      source = File.read!(@channel_ex)

      assert source =~
               "GenServer.call(lv_pid, {@prefix, :async_pids}, :infinity)"

      assert source =~ "defp all_async_pids(state) do"
    end
  end

  describe "1.2.11 HTMLFormatter early-close migration still holds" do
    test "prefix-depth gate refuses to migrate expressions that close at depth 0" do
      source = File.read!(@html_algebra_ex)

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
