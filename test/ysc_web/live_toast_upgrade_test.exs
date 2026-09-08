defmodule YscWeb.LiveToastUpgradeTest do
  @moduledoc """
  Guards the live_toast 0.9.0 → 0.10.2 upgrade.

  0.10.0 stops calling gettext on `put_toast`/`send_toast` copy; connection-notice
  translation is opt-in via `:gettext_backend`. 0.10.1/0.10.2 fix custom Phoenix
  flash rerenders. We pass English strings through `YscWeb.Flash` and do not
  configure `:gettext_backend` or `toast_component_fn`.
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

  describe "0.10.2 Hex lock and public APIs" do
    test "locks the Hex package to 0.10.2" do
      assert to_string(Application.spec(:live_toast, :vsn)) == "0.10.2"
    end

    test "APIs we call still exist" do
      assert function_exported?(LiveToast, :put_toast, 3)
      assert function_exported?(LiveToast, :put_toast, 4)
      assert function_exported?(LiveToast, :send_toast, 2)
      assert function_exported?(LiveToast, :send_toast, 3)
      assert function_exported?(LiveToast, :toast_group, 1)
      assert function_exported?(LiveToast, :group_class_fn, 1)
    end

    test "package elixir requirement is 1.15 which we satisfy" do
      mix_exs =
        File.read!(Path.expand("../../deps/live_toast/mix.exs", __DIR__))

      assert mix_exs =~ ~s(elixir: "~> 1.15")
      assert Version.match?(System.version(), "~> 1.15")
    end
  end

  describe "0.10.0 gettext breaking change" do
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

  describe "call sites still match 0.10 APIs" do
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
      refute source =~ "gettext_backend"
    end

    test "app.js still initializes the hook with duration and max items" do
      source = File.read!(@app_js)
      assert source =~ ~s[from "../vendor/live_toast.esm.js"]
      assert source =~ "createLiveToastHook(TOAST_DURATION_MS, MAX_TOAST_ITEMS)"
    end

    test "vendored ESM matches the 0.10.2 package bundle and exports the hook" do
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
