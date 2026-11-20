defmodule YscWeb.PhoenixLiveViewUpgradeTest do
  @moduledoc """
  Guards the phoenix_live_view 1.2.13 → 1.2.14 upgrade.

  1.2.14 patches EEF-CVE-2026-126334 (MEDIUM / GHSA-v4p7-3pm2-wq6c):
  a router-mounted LiveView joined without `"url"` or `"redirect"`
  used to skip its `live_session` `on_mount` hooks. Auth, onboarding,
  and admin checks live in those hooks (`YscWeb.UserAuth`), so a
  crafted `phx_join` could mount the LiveView after the HTTP render
  had already passed. Nested LiveViews still join without a URL.
  Do not add this CVE to `ignore_advisories`.

  1.2.13 still applies: upload FileReader errors and chunk timeouts
  fail the entry; auto_upload waits for every ancestor lock; live-link
  clicks on nested children honor target/download; form recovery
  completion order; reload-status cookies; JS.focus retry. Socket
  options such as `:max_channels_per_transport` forward through
  `use Phoenix.LiveView.Socket`. We auto_upload receipts, avatars,
  and media, nest children inside `<.link navigate>`, and pass
  `disconnectedTimeout: 1000`. We do not set `formtarget`,
  ColocatedCSS, `onDocumentPatch`, or `:max_channels_per_transport`.
  `phoenix_template` stays 1.0.4.
  """
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.JS

  @live_view_js Path.expand(
                  "../../deps/phoenix_live_view/priv/static/phoenix_live_view.js",
                  __DIR__
                )
  @entry_uploader_js Path.expand(
                       "../../deps/phoenix_live_view/assets/js/phoenix_live_view/entry_uploader.js",
                       __DIR__
                     )
  @upload_entry_js Path.expand(
                     "../../deps/phoenix_live_view/assets/js/phoenix_live_view/upload_entry.js",
                     __DIR__
                   )
  @element_ref_ts Path.expand(
                    "../../deps/phoenix_live_view/assets/js/phoenix_live_view/element_ref.ts",
                    __DIR__
                  )
  @js_js Path.expand(
           "../../deps/phoenix_live_view/assets/js/phoenix_live_view/js.js",
           __DIR__
         )
  @live_socket_ts Path.expand(
                    "../../deps/phoenix_live_view/assets/js/phoenix_live_view/live_socket.ts",
                    __DIR__
                  )
  @view_ts Path.expand(
             "../../deps/phoenix_live_view/assets/js/phoenix_live_view/view.ts",
             __DIR__
           )
  @socket_ex Path.expand(
               "../../deps/phoenix_live_view/lib/phoenix_live_view/socket.ex",
               __DIR__
             )
  @changelog Path.expand("../../deps/phoenix_live_view/CHANGELOG.md", __DIR__)
  @channel_ex Path.expand(
                "../../deps/phoenix_live_view/lib/phoenix_live_view/channel.ex",
                __DIR__
              )
  @session_ex Path.expand(
                "../../deps/phoenix_live_view/lib/phoenix_live_view/session.ex",
                __DIR__
              )
  @static_ex Path.expand(
               "../../deps/phoenix_live_view/lib/phoenix_live_view/static.ex",
               __DIR__
             )
  @router_ex Path.expand("../../lib/ysc_web/router.ex", __DIR__)
  @async_ex Path.expand(
              "../../deps/phoenix_live_view/lib/phoenix_live_view/async.ex",
              __DIR__
            )
  @html_algebra_ex Path.expand(
                     "../../deps/phoenix_live_view/lib/phoenix_live_view/html_algebra.ex",
                     __DIR__
                   )
  @app_js Path.expand("../../assets/js/app.js", __DIR__)
  @endpoint_ex Path.expand("../../lib/ysc_web/endpoint.ex", __DIR__)
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @admin_search_ex Path.expand(
                     "../../lib/ysc_web/components/admin_search.ex",
                     __DIR__
                   )
  @live_phone_ex Path.expand(
                   "../../lib/ysc_web/components/live_phone.ex",
                   __DIR__
                 )
  @dashboard_link_ex Path.expand(
                       "../../lib/ysc_web/components/admin_components.ex",
                       __DIR__
                     )

  @auto_upload_files [
    "lib/ysc_web/components/image_upload_component.ex",
    "lib/ysc_web/components/media_picker_component.ex",
    "lib/ysc_web/components/uploader/upload_component.ex",
    "lib/ysc_web/live/admin/admin_media_live.ex",
    "lib/ysc_web/live/event_photo_upload_live.ex",
    "lib/ysc_web/live/expense_report_live.ex",
    "lib/ysc_web/live/post_migration_onboarding_live.ex",
    "lib/ysc_web/live/user_settings_live.ex"
  ]

  describe "1.2.14 Hex lock and public APIs" do
    test "locks the Hex package to 1.2.14" do
      assert to_string(Application.spec(:phoenix_live_view, :vsn)) == "1.2.14"
      assert File.read!(@mix_exs) =~ ~s({:phoenix_live_view, "~> 1.2.14"})
      refute File.read!(@mix_exs) =~ ~s({:phoenix_live_view, "~> 1.2.13"})

      lock = File.read!(@mix_lock)

      assert lock =~
               ~s|"phoenix_live_view": {:hex, :phoenix_live_view, "1.2.14"|

      refute lock =~
               ~s|"phoenix_live_view": {:hex, :phoenix_live_view, "1.2.13"|
    end

    test "does not ignore the patched advisory" do
      mix_exs = File.read!(@mix_exs)

      ignore =
        mix_exs
        |> String.split("ignore_advisories: [", parts: 2)
        |> Enum.at(1)
        |> String.split("]", parts: 2)
        |> hd()

      refute ignore =~ "EEF-CVE-2026-126334"
    end

    test "companion phoenix_template lock stays 1.0.4" do
      assert to_string(Application.spec(:phoenix_template, :vsn)) == "1.0.4"
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
      refute lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.1.0"|
    end

    test "changelog records the 1.2.14 security heading" do
      changelog = File.read!(@changelog)
      assert changelog =~ "## v1.2.14 (2026-11-20)"
      assert changelog =~ "CVE-2026-126334"
      assert changelog =~ "live_session"
      assert changelog =~ "on_mount"
    end

    test "changelog still records the 1.2.13 patch heading" do
      changelog = File.read!(@changelog)
      assert changelog =~ "## v1.2.13 (2026-10-20)"
      assert changelog =~ "Handle file reader upload error"
      assert changelog =~ "Wait for all ancestor looks before auto upload"

      assert changelog =~
               "Respect live link target and download attributes on child clicks"
    end

    test "allow_upload, consume_uploaded_entries, and JS.push still exist" do
      {:module, Phoenix.LiveView} = Code.ensure_loaded(Phoenix.LiveView)

      {:module, Phoenix.LiveView.Upload} =
        Code.ensure_loaded(Phoenix.LiveView.Upload)

      {:module, JS} = Code.ensure_loaded(JS)

      assert function_exported?(Phoenix.LiveView, :allow_upload, 3)
      assert function_exported?(Phoenix.LiveView, :consume_uploaded_entries, 3)
      assert function_exported?(JS, :push, 1)
      assert function_exported?(JS, :push, 2)
      assert function_exported?(JS, :push, 3)
    end
  end

  describe "EEF-CVE-2026-126334 live_session on_mount skip" do
    test "router-mounted joins without url or redirect are unauthorized" do
      source = File.read!(@channel_ex)

      assert source =~
               "defp authorize_session(%Session{route_required?: true}, _endpoint, %{}) do"

      assert source =~
               "Router-mounted LiveViews need a route to load the live_session hooks"

      assert source =~ "{:error, :unauthorized}"
    end

    test "nested LiveViews can still join without a URL" do
      source = File.read!(@channel_ex)

      assert source =~
               "defp authorize_session(%Session{} = session, _endpoint, %{}) do"

      assert source =~ "{:ok, session, _route = nil, _url = nil}"
    end

    test "root session tokens mark route_required; nested tokens do not" do
      static = File.read!(@static_ex)
      session = File.read!(@session_ex)

      assert static =~ "route_required?: not is_nil(router),"
      assert static =~ "route_required?: false,"
      assert session =~ "route_required?: route_required?(session),"

      assert session =~
               "defp route_required?(%{route_required?: required?}), do: required?"
    end

    test "auth live_sessions still declare UserAuth on_mount in the router" do
      source = File.read!(@router_ex)

      assert source =~ "live_session :require_authenticated_user,"
      assert source =~ "{YscWeb.UserAuth, :ensure_authenticated}"
      assert source =~ "{YscWeb.UserAuth, :ensure_onboarding_complete}"
      assert source =~ "live_session :require_admin,"
      assert source =~ "{YscWeb.UserAuth, :ensure_admin}"
    end
  end

  describe "1.2.13 upload file-reader, chunk timeout, and errored entries" do
    test "FileReader errors fail the entry instead of hanging the uploader" do
      source = File.read!(@entry_uploader_js)

      assert source =~ ~s|const onError = () => {|
      assert source =~ ~s|"upload.read-failed"|
      assert source =~ ~s|this.error("failed")|
      assert source =~ "reader.onerror = onError"
      assert source =~ "reader.onabort = onError"
    end

    test "chunk push timeouts fail the entry" do
      source = File.read!(@entry_uploader_js)
      assert source =~ ~s|.receive("timeout", () => this.error("timeout"))|
    end

    test "failed entries always complete so the form loading ref is released" do
      source = File.read!(@upload_entry_js)

      assert source =~ "fail(reason, notifyServer) {"
      assert source =~ "this._isDone = true"

      assert source =~ """
                 } finally {
                   this._onDone();
                 }
             """
    end

    test "blocked upload submits emit a diagnostic instead of looking like a no-op" do
      js = File.read!(@live_view_js)
      view = File.read!(@view_ts)

      assert js =~ "upload.submit-blocked"
      assert view =~ "logBlockedSubmit("
      assert view =~ ~s|"entry-errors"|
      assert view =~ ~s|"upload-failed"|
    end

    test "app LiveViews still auto_upload with allow_upload/3" do
      {:module, Phoenix.LiveView} = Code.ensure_loaded(Phoenix.LiveView)
      assert function_exported?(Phoenix.LiveView, :allow_upload, 3)

      Enum.each(@auto_upload_files, fn relative_path ->
        path = Path.expand("../../#{relative_path}", __DIR__)
        contents = File.read!(path)

        assert contents =~ "allow_upload(",
               "#{relative_path} must still call allow_upload/3"

        assert contents =~ "auto_upload: true",
               "#{relative_path} must still opt into auto_upload"
      end)
    end
  end

  describe "1.2.13 auto_upload waits for ancestor locks" do
    test "onUnlock rechecks after each undo instead of starting on the nearest lock" do
      source = File.read!(@element_ref_ts)

      assert source =~ "static onUnlock(el, callback)"
      assert source =~ "if (e.target !== closestLock) return"
      assert source =~ "ElementRef.onUnlock(el, callback)"
    end

    test "auto_upload starts only after the input's ancestor chain is unlocked" do
      source = File.read!(@view_ts)

      assert source =~ "ElementRef.onUnlock(inputEl, () => {"
      assert source =~ "LiveUploader.filesAwaitingPreflight(inputEl).length > 0"
    end
  end

  describe "1.2.13 live-link target/download on child clicks" do
    test "wantsNewTab uses the live-link element, not the click target" do
      js = File.read!(@live_view_js)
      live_socket = File.read!(@live_socket_ts)

      assert js =~ "wantsNewTab(e, el = e.target)"
      assert js =~ "el.hasAttribute(\"download\")"
      assert live_socket =~ "DOM.wantsNewTab(e, target)"
    end

    test "submitter formtarget is read for unloadable form submits" do
      js = File.read!(@live_view_js)

      assert js =~ "e.submitter.hasAttribute(\"formtarget\")"
      assert js =~ "e.submitter.getAttribute(\"formtarget\")"
    end

    test "app dashboard live links still nest children inside the anchor" do
      source = File.read!(@dashboard_link_ex)
      assert source =~ ~s|<.link id={@id} navigate={@navigate} class={@class}>|
      assert source =~ "render_slot(@inner_block)"
    end
  end

  describe "1.2.13 form recovery completion and reload cookie" do
    test "mount patch waits until every recovered form has finished" do
      source = File.read!(@view_ts)

      assert source =~ "this.pendingForms.delete(newForm.id)"
      assert source =~ "formsRecovered++"
      assert source =~ "if (formsRecovered === formsToRecover.length)"
    end

    test "client deletes the reload-status cookie on the next navigation" do
      live_socket = File.read!(@live_socket_ts)
      js = File.read!(@live_view_js)

      assert live_socket =~ "resetReloadStatus()"
      assert live_socket =~ "Browser.deleteCookie(PHX_RELOAD_STATUS)"
      assert js =~ ~s|"__phoenix_reload_status__"|
    end
  end

  describe "1.2.13 focus retry and disconnected timer" do
    test "focusWithRetry skips the second attempt when focus already moved" do
      source = File.read!(@js_js)

      assert source =~ "focusWithRetry(callback)"
      assert source =~ "if (document.activeElement === activeElement)"
    end

    test "pending disconnected timer is cleared before reconnect and not stacked" do
      view = File.read!(@view_ts)

      assert view =~ "if (this.disconnectedTimer != null)"

      assert view =~
               "this.disconnectedTimer != null && clearTimeout(this.disconnectedTimer)"
    end

    test "app LiveSocket still sets disconnectedTimeout" do
      assert File.read!(@app_js) =~ "disconnectedTimeout: 1000"
    end
  end

  describe "1.2.13 socket options and unused APIs" do
    test "use Phoenix.LiveView.Socket forwards options to Phoenix.Socket" do
      source = File.read!(@socket_ex)

      assert source =~ "use Phoenix.Socket, unquote(opts)"
      assert source =~ "max_channels_per_transport: 200"
    end

    test "endpoint mounts Phoenix.LiveView.Socket without a channel cap override" do
      source = File.read!(@endpoint_ex)

      assert source =~ ~s|socket "/live", Phoenix.LiveView.Socket,|
      refute source =~ "max_channels_per_transport"
    end

    test "app does not opt into formtarget, ColocatedCSS, or onDocumentPatch" do
      app_js = File.read!(@app_js)
      refute app_js =~ "onDocumentPatch"

      lib_files =
        Path.wildcard(Path.expand("../../lib/**/*.{ex,heex}", __DIR__))

      Enum.each(lib_files, fn path ->
        contents = File.read!(path)

        refute contents =~ "formtarget",
               "#{Path.relative_to_cwd(path)} must not set formtarget"

        refute contents =~ "ColocatedCSS",
               "#{Path.relative_to_cwd(path)} must not use ColocatedCSS"
      end)
    end
  end

  describe "1.2.12 JS.push encoding and client opts still hold" do
    test "encodes event, value, and LiveComponent target without dropping payload" do
      cid = %Phoenix.LiveComponent.CID{cid: 7}

      js =
        JS.push("delete", target: cid, value: %{id: "item-1"})
        |> JS.push("lv:clear-flash", value: %{key: :info})

      assert %JS{ops: ops} = js

      assert ["push", %{event: "delete", target: 7, value: %{id: "item-1"}}] in ops

      assert ["push", %{event: "lv:clear-flash", value: %{key: :info}}] in ops
    end

    test "rejects a non-map :value the same way as 1.2.12" do
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

  describe "1.2.12 hook disconnected runs once still holds" do
    test "JS client only calls disconnected() when not already disconnected" do
      js = File.read!(@live_view_js)

      assert js =~ "if (!this.__isDisconnected) {"
      assert js =~ "this.__isDisconnected = true;"
      assert js =~ "this.disconnected();"
    end
  end

  describe "1.2.12 assign_async falsy keys still hold" do
    test "missing-key check uses Enum.any? so false/0 keys are detected" do
      source = File.read!(@async_ex)

      assert source =~
               "if Enum.any?(keys, &(not is_map_key(assigns, &1))) do"

      refute source =~ "Enum.find(keys, &(not is_map_key(assigns, &1)))"
    end
  end

  describe "1.2.12 caret restore for search and tel inputs still holds" do
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
