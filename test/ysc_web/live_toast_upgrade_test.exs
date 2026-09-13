defmodule YscWeb.LiveToastUpgradeTest do
  @moduledoc """
  Guards the live_toast 0.10.2 → 0.11.0 upgrade.

  0.11.0 is a minor: default toast styles work with Tailwind 3.4 and 4.x
  (`z-[100]`, stacked arbitrary variants, explicit `border-gray-200`), and
  connection notices remove the HTML `hidden` attribute before showing so
  Tailwind 4 does not keep them `display: none`. `createLiveToastHook/2`,
  `put_toast`, `send_toast`, and `toast_group` are unchanged.

  We stay on Tailwind 3.3.2, do not pass `toast_class_fn`, and keep
  `transform` on our custom `group_class_fn` so center corners still
  translate under Tailwind 3. We still do not configure `:gettext_backend`.
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.ConnTest

  alias YscWeb.Flash
  alias YscWeb.Layouts

  @live_toast Path.expand(
                "../../deps/live_toast/lib/live_toast.ex",
                __DIR__
              )
  @live_component Path.expand(
                    "../../deps/live_toast/lib/live_toast/live_component.ex",
                    __DIR__
                  )
  @utility Path.expand(
             "../../deps/live_toast/lib/live_toast/utility.ex",
             __DIR__
           )
  @components Path.expand(
                "../../deps/live_toast/lib/live_toast/components.ex",
                __DIR__
              )
  @flash Path.expand("../../lib/ysc_web/flash.ex", __DIR__)
  @layouts Path.expand("../../lib/ysc_web/components/layouts.ex", __DIR__)
  @app_js Path.expand("../../assets/js/app.js", __DIR__)
  @vendor_js Path.expand("../../assets/vendor/live_toast.esm.js", __DIR__)
  @package_js Path.expand(
                "../../deps/live_toast/priv/static/live_toast.esm.js",
                __DIR__
              )

  setup_all do
    {:module, LiveToast} = Code.ensure_loaded(LiveToast)
    {:module, LiveToast.Utility} = Code.ensure_loaded(LiveToast.Utility)
    :ok
  end

  defp conn_with_flash(conn) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> fetch_flash()
  end

  defp class_string(assigns) do
    assigns
    |> LiveToast.toast_class_fn()
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end

  describe "0.11.0 Hex lock and public APIs" do
    test "locks the Hex package to 0.11.0" do
      assert to_string(Application.spec(:live_toast, :vsn)) == "0.11.0"
    end

    test "APIs we call still exist" do
      assert function_exported?(LiveToast, :put_toast, 3)
      assert function_exported?(LiveToast, :put_toast, 4)
      assert function_exported?(LiveToast, :send_toast, 2)
      assert function_exported?(LiveToast, :send_toast, 3)
      assert function_exported?(LiveToast, :toast_group, 1)
      assert function_exported?(LiveToast, :group_class_fn, 1)
      assert function_exported?(LiveToast, :toast_class_fn, 1)
    end

    test "package elixir requirement is 1.15 which we satisfy" do
      mix_exs =
        File.read!(Path.expand("../../deps/live_toast/mix.exs", __DIR__))

      assert mix_exs =~ ~s(elixir: "~> 1.15")
      assert Version.match?(System.version(), "~> 1.15")
    end
  end

  describe "0.11.0 Tailwind 3/4 default styles" do
    test "default toast_class_fn uses z-[100] and explicit gray border" do
      classes = class_string(%{kind: :info, rest: %{}})

      assert classes =~ "z-[100]"
      assert classes =~ "border-gray-200"
      refute classes =~ ~r/(^|\s)z-100(\s|$)/
    end

    test "default toast_class_fn uses stacked arbitrary variants for scripting" do
      classes = class_string(%{kind: :info, rest: %{}})

      assert classes =~
               "[@media(scripting:enabled)]:[[data-phx-main]_&]:opacity-100"

      refute classes =~ "[@media(scripting:enabled){[data-phx-main]_&}]"
    end

    test "error toasts force the red border against Tailwind 4 border defaults" do
      classes = class_string(%{kind: :error, rest: %{}})
      assert classes =~ "!border-red-200"
      assert classes =~ "!bg-red-100"
    end

    test "close button uses Tailwind 3/4 compatible focus outline utilities" do
      source = File.read!(@components)
      assert source =~ "cursor-pointer"
      assert source =~ "focus:[outline:2px_solid_transparent]"
      assert source =~ "focus:ring-black/20"
    end
  end

  describe "0.11.0 hidden-attribute connection notices" do
    test "Utility.show/2 removes hidden before JS.show display flex" do
      source = File.read!(@utility)
      assert source =~ ~s[JS.remove_attribute("hidden", to: selector)]
      assert source =~ "display: \"flex\""

      js = LiveToast.Utility.show("#client-error")
      ops = inspect(js.ops)
      assert ops =~ "remove_attr"
      assert ops =~ "hidden"
      assert ops =~ "show"
      assert ops =~ "flex"
    end

    test "vendored hook removes the hidden attribute before showing" do
      vendor = File.read!(@vendor_js)
      assert vendor =~ ~s[this.el.removeAttribute("hidden")]
      assert vendor =~ "this.el.style.display = \"flex\""
    end
  end

  describe "0.10.0 gettext breaking change still holds" do
    test "does not configure gettext_backend so connection notices stay English" do
      assert Application.get_env(:live_toast, :gettext_backend) == nil
    end

    test "LiveToast.Gettext backend module is gone" do
      assert {:error, :nofile} = Code.ensure_loaded(LiveToast.Gettext)
    end

    test "Utility.translate/1 returns the supplied string when no backend is set" do
      assert LiveToast.Utility.translate("We can't find the internet") ==
               "We can't find the internet"

      assert LiveToast.Utility.translate("Upload successful.") ==
               "Upload successful."
    end

    test "live component no longer gettext-translates toast title and body" do
      source = File.read!(@live_component)
      assert source =~ "title={title}"
      assert source =~ "{msg}"
      refute source =~ "Utility.translate(title)"
      refute source =~ "Utility.translate(msg)"
    end

    test "utility only dgettexts when gettext_backend is configured" do
      source = File.read!(@utility)
      assert source =~ ~s[Application.get_env(:live_toast, :gettext_backend)]
      assert source =~ "nil -> message"
      assert source =~ ~s[Gettext.dgettext(backend, "live_toast", message)]
    end
  end

  describe "call sites still match 0.11 APIs" do
    test "Flash.put_toast still stores Conn title separately because LiveToast ignores Conn opts" do
      source = File.read!(@live_toast)
      assert source =~ "def put_toast(%Plug.Conn{} = conn, kind, msg, _options)"

      flash = File.read!(@flash)
      assert flash =~ "LiveToast.put_toast(conn, kind, msg, opts)"
      assert flash =~ ~s["\#{kind}_toast_title"]
    end

    test "Flash.send_toast still forwards kind, msg, and default icon opts" do
      source = File.read!(@flash)

      assert source =~
               "LiveToast.send_toast(kind, msg, default_icon_opts(kind, opts))"
    end

    test "layout still passes flash, connected, and toasts_sync to toast_group" do
      source = File.read!(@layouts)
      assert source =~ "import LiveToast, only: [toast_group: 1]"
      assert source =~ "flash={@flash_for_toast}"
      assert source =~ "connected={@connected}"
      assert source =~ "toasts_sync={@toasts_sync}"
      assert source =~ "group_class_fn={&YscWeb.Layouts.toast_group_class_fn/1}"
      refute source =~ "toast_component_fn"
      refute source =~ "toast_class_fn"
      refute source =~ "gettext_backend"
    end

    test "custom group_class_fn keeps Tailwind 3 transform on center corners" do
      bottom = Layouts.toast_group_class_fn(%{corner: :bottom_center})
      top = Layouts.toast_group_class_fn(%{corner: :top_center})

      assert Enum.any?(bottom, fn
               class when is_binary(class) ->
                 class =~ "transform -translate-x-1/2"

               _ ->
                 false
             end)

      assert Enum.any?(top, fn
               class when is_binary(class) ->
                 class =~ "transform -translate-x-1/2"

               _ ->
                 false
             end)

      default = LiveToast.group_class_fn(%{corner: :top_center})
      joined = default |> Enum.filter(&is_binary/1) |> Enum.join(" ")
      refute joined =~ "transform"
    end

    test "app.js still initializes the hook with duration and max items" do
      source = File.read!(@app_js)
      assert source =~ ~s[from "../vendor/live_toast.esm.js"]
      assert source =~ "createLiveToastHook(TOAST_DURATION_MS, MAX_TOAST_ITEMS)"
    end

    test "vendored ESM matches the 0.11.0 package bundle and exports the hook" do
      vendor = File.read!(@vendor_js)
      package = File.read!(@package_js)
      assert vendor == package
      assert vendor =~ "function createLiveToastHook"
      assert vendor =~ "function asToastElement"
      refute vendor =~ "interface HTMLElement"
    end
  end

  describe "YscWeb.Flash still stores flashes without LiveToast gettext" do
    test "put_toast on Conn keeps the supplied message and title", %{conn: conn} do
      conn =
        conn
        |> conn_with_flash()
        |> Flash.put_toast(:info, "Saved successfully.", title: "Done")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Saved successfully."

      assert Phoenix.Flash.get(conn.assigns.flash, "info_toast_title") ==
               "Done"
    end

    test "send_toast still returns a UUID without translating the body" do
      uuid = Flash.send_toast(:info, "Upload successful.")
      assert is_binary(uuid)
      assert byte_size(uuid) == 36
    end

    test "promoted redirect toasts keep application copy unchanged" do
      msg = "Saved successfully."

      assert {[%LiveToast{kind: :info, msg: ^msg, title: "Done"}], flash} =
               Layouts.toasts_sync_with_flash(%{
                 toasts_sync: [],
                 flash: %{
                   "info" => msg,
                   "info_toast_title" => "Done"
                 }
               })

      assert flash["info"] == msg
    end
  end
end
