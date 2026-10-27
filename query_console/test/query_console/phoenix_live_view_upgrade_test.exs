defmodule QueryConsole.PhoenixLiveViewUpgradeTest do
  @moduledoc """
  Guards the phoenix_live_view 1.1.32 → 1.1.33 upgrade.

  1.1.33 is a patch (2026-08-10). It patches EEF-CVE-2026-64941 (LOW /
  GHSA-36m4-rm57-3prf): `validate_local_url!/2` now rejects ASCII tab,
  LF, CR, and encoded tab (`/%09`) in `redirect/2`, `push_navigate/2`,
  and `push_patch/2` `:to` paths. Browsers strip those characters before
  URL parsing, so `/\\t/evil.com` used to pass as a local path and then
  resolve as a scheme-relative open redirect. Only `redirect/2` is the
  sink; live navigation expands against the current origin.

  lotus_web still requires `< 1.2.0`, so Query Console stays on 1.1.x.
  We only pass compile-time `~p` paths (`/auth/ysc`, `/`, `/workbooks/:id`)
  and do not forward user input to `Phoenix.LiveView.redirect/2`.
  `phoenix_template` stays 1.0.4.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/phoenix_live_view/CHANGELOG.md", __DIR__)
  @live_view_ex Path.expand(
                  "../../deps/phoenix_live_view/lib/phoenix_live_view.ex",
                  __DIR__
                )
  @lotus_web_mix Path.expand("../../deps/lotus_web/mix.exs", __DIR__)
  @user_auth_ex Path.expand("../../lib/query_console_web/user_auth.ex", __DIR__)
  @console_live_ex Path.expand(
                     "../../lib/query_console_web/live/console_live.ex",
                     __DIR__
                   )
  @auth_controller_ex Path.expand(
                        "../../lib/query_console_web/controllers/auth_controller.ex",
                        __DIR__
                      )
  @endpoint_ex Path.expand("../../lib/query_console_web/endpoint.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:phoenix_live_view)
    {:module, Phoenix.LiveView} = Code.ensure_loaded(Phoenix.LiveView)

    {:module, Phoenix.LiveView.Socket} =
      Code.ensure_loaded(Phoenix.LiveView.Socket)

    :ok
  end

  describe "1.1.33 Hex lock and public APIs" do
    test "locks the Hex package to 1.1.33" do
      assert to_string(Application.spec(:phoenix_live_view, :vsn)) == "1.1.33"
    end

    test "mix.exs pins the patched 1.1.x floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:phoenix_live_view, "~> 1.1.33"})
      refute mix_exs =~ ~s({:phoenix_live_view, "~> 1.1.0"})
    end

    test "companion lock is 1.1.33 and phoenix_template stays 1.0.4" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"phoenix_live_view": {:hex, :phoenix_live_view, "1.1.33"|
      refute lock =~ ~s|"phoenix_live_view": {:hex, :phoenix_live_view, "1.1.32"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
      refute lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.1.0"|

      assert to_string(Application.spec(:phoenix_template, :vsn)) == "1.0.4"
    end

    test "lotus_web still requires LiveView below 1.2.0" do
      assert File.read!(@lotus_web_mix) =~
               ~s({:phoenix_live_view, ">= 1.0.0 and < 1.2.0"})
    end

    test "redirect, push_navigate, and push_patch still exist" do
      {:module, Phoenix.LiveView} = Code.ensure_loaded(Phoenix.LiveView)
      assert function_exported?(Phoenix.LiveView, :redirect, 1)
      assert function_exported?(Phoenix.LiveView, :redirect, 2)
      assert function_exported?(Phoenix.LiveView, :push_navigate, 2)
      assert function_exported?(Phoenix.LiveView, :push_patch, 2)
    end
  end

  describe "1.1.33 changelog" do
    test "documents CVE-2026-64941 under the v1.1.33 heading" do
      changelog = File.read!(@changelog)
      heading = changelog_section(changelog, "v1.1.33")

      assert heading
      assert heading =~ "CVE-2026-64941"
      assert heading =~ "open redirect"
      assert heading =~ "ASCII tab, LF and CR"
      refute heading =~ "v1.1.32"
    end
  end

  describe "EEF-CVE-2026-64941 local URL guard" do
    test "source rejects tab, encoded tab, LF, CR, and backslash" do
      source = File.read!(@live_view_ex)
      assert source =~ ~S|@invalid_local_url_chars ["\\", "/%09", "/\t", "\n", "\r"]|
    end

    test "valid local paths still redirect" do
      socket = Phoenix.LiveView.redirect(new_socket(), to: "/auth/ysc")
      assert socket.redirected == {:redirect, %{to: "/auth/ysc", status: 302}}
    end

    test "leading // still raises as a non-path" do
      assert_raise ArgumentError, ~r/expects a path/, fn ->
        Phoenix.LiveView.redirect(new_socket(), to: "//example.com")
      end
    end

    test "tab after the leading slash raises as unsafe" do
      assert_raise ArgumentError, ~r/unsafe characters detected for redirect\/2/, fn ->
        Phoenix.LiveView.redirect(new_socket(), to: "/\t/example.com")
      end
    end

    test "encoded tab /%09 after the leading slash raises as unsafe" do
      assert_raise ArgumentError, ~r/unsafe characters detected for redirect\/2/, fn ->
        Phoenix.LiveView.redirect(new_socket(), to: "/%09/example.com")
      end
    end

    test "LF and CR in the path raise as unsafe" do
      assert_raise ArgumentError, ~r/unsafe characters detected for redirect\/2/, fn ->
        Phoenix.LiveView.redirect(new_socket(), to: "/\n/example.com")
      end

      assert_raise ArgumentError, ~r/unsafe characters detected for redirect\/2/, fn ->
        Phoenix.LiveView.redirect(new_socket(), to: "/\r/example.com")
      end
    end

    test "backslash in the path still raises as unsafe" do
      assert_raise ArgumentError, ~r/unsafe characters detected for redirect\/2/, fn ->
        Phoenix.LiveView.redirect(new_socket(), to: "/\\/example.com")
      end
    end

    test "push_navigate and push_patch share the same guard" do
      assert_raise ArgumentError, ~r/unsafe characters detected for push_navigate\/2/, fn ->
        Phoenix.LiveView.push_navigate(new_socket(), to: "/\t/example.com")
      end

      assert_raise ArgumentError, ~r/unsafe characters detected for push_patch\/2/, fn ->
        Phoenix.LiveView.push_patch(new_socket(), to: "/%09/example.com")
      end
    end

    test "push_patch still accepts a local workbook path" do
      socket = Phoenix.LiveView.push_patch(new_socket(), to: "/workbooks/1")
      assert socket.redirected == {:live, :patch, %{to: "/workbooks/1", kind: :push}}
    end
  end

  describe "Query Console still uses compile-time local paths" do
    test "LiveView auth gate redirects to ~p /auth/ysc" do
      source = File.read!(@user_auth_ex)

      assert source =~
               ~s|Phoenix.LiveView.redirect(socket, to: ~p"/auth/ysc")|
    end

    test "console live navigation uses ~p paths" do
      source = File.read!(@console_live_ex)
      assert source =~ ~S|push_patch(socket, to: ~p"/workbooks/#{first.id}")|
      assert source =~ ~s|push_navigate(to: ~p"/")|
      refute source =~ "redirect(socket, to: params"
      refute source =~ "redirect(socket, to: %{"
    end

    test "controller SSO redirects stay on Phoenix.Controller, not LiveView" do
      source = File.read!(@auth_controller_ex)
      assert source =~ ~s|redirect(to: ~p"/auth/ysc")|
      assert source =~ "redirect(external: url)"
      assert source =~ "redirect(external: SSO.build_logout_url())"
      refute source =~ "Phoenix.LiveView.redirect"
    end

    test "endpoint still mounts LiveView over websocket and longpoll" do
      source = File.read!(@endpoint_ex)
      assert source =~ ~s|socket "/live", Phoenix.LiveView.Socket,|
      assert source =~ "websocket: [connect_info: [session: @session_options]]"
      assert source =~ "longpoll: [connect_info: [session: @session_options]]"
    end
  end

  defp new_socket do
    %Phoenix.LiveView.Socket{}
  end

  defp changelog_section(changelog, version) do
    changelog
    |> String.split("\n## ")
    |> Enum.find_value(fn section ->
      heading = String.replace_prefix(section, "## ", "")

      if String.starts_with?(heading, version) do
        heading
      end
    end)
  end
end
