defmodule Ysc.ChromicPdfUpgradeTest do
  @moduledoc """
  Guards the chromic_pdf 1.17.1 → 1.17.2 upgrade.

  1.17.2 is a patch with no documented breaking changes. `SpawnSession`
  used to create each Chrome target in a private browser context with
  `disposeOnDetach: true`. On detach (session recycle, pool stop, BEAM
  exit) that flag races Chrome's quit and can leave a headless Chrome
  process behind (#349). 1.17.2 drops `disposeOnDetach` and
  `CloseTarget` now detaches then calls `Target.disposeBrowserContext`.
  Channel traps exits so `Browser.close` still goes out on shutdown,
  and SessionPool closes workers on `:shutdown` instead of skipping.

  We start `{ChromicPDF, Application.get_env(:ysc, ChromicPDF, [])}`
  when enabled and capture TV posters with
  `ChromicPDF.capture_screenshot/2` (`{:html, html}`, `full_page`,
  `evaluate`, `timeout`). We do not call `print_to_pdf/2`, pass
  `:timezone`, or use `on_demand`. Public capture/print APIs are
  unchanged. Tests keep ChromicPDF disabled.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/chromic_pdf/CHANGELOG.md", __DIR__)
  @close_target Path.expand(
                  "../../deps/chromic_pdf/lib/chromic_pdf/pdf/protocols/close_target.ex",
                  __DIR__
                )
  @spawn_session Path.expand(
                   "../../deps/chromic_pdf/lib/chromic_pdf/pdf/protocols/spawn_session.ex",
                   __DIR__
                 )
  @channel Path.expand(
             "../../deps/chromic_pdf/lib/chromic_pdf/pdf/browser/channel.ex",
             __DIR__
           )
  @session_pool Path.expand(
                  "../../deps/chromic_pdf/lib/chromic_pdf/pdf/browser/session_pool.ex",
                  __DIR__
                )
  @browser Path.expand(
             "../../deps/chromic_pdf/lib/chromic_pdf/pdf/browser.ex",
             __DIR__
           )
  @chromic Path.expand(
             "../../lib/ysc/events/tv_poster_image/chromic.ex",
             __DIR__
           )
  @application Path.expand("../../lib/ysc/application.ex", __DIR__)
  @config Path.expand("../../config/config.exs", __DIR__)
  @test_config Path.expand("../../config/test.exs", __DIR__)
  @sentry_filter Path.expand("../../lib/ysc/sentry_logger_filter.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:chromic_pdf)
    {:module, ChromicPDF} = Code.ensure_loaded(ChromicPDF)

    {:module, ChromicPDF.CloseTarget} =
      Code.ensure_loaded(ChromicPDF.CloseTarget)

    {:module, ChromicPDF.SpawnSession} =
      Code.ensure_loaded(ChromicPDF.SpawnSession)

    {:module, ChromicPDF.Browser.Channel} =
      Code.ensure_loaded(ChromicPDF.Browser.Channel)

    {:module, ChromicPDF.ChromeError} =
      Code.ensure_loaded(ChromicPDF.ChromeError)

    {:module, ChromicPDF.Browser.ExecutionError} =
      Code.ensure_loaded(ChromicPDF.Browser.ExecutionError)

    :ok
  end

  describe "1.17.2 Hex lock and public APIs" do
    test "locks chromic_pdf to 1.17.2" do
      {:module, _} = Code.ensure_loaded(ChromicPDF)
      assert to_string(Application.spec(:chromic_pdf, :vsn)) == "1.17.2"
    end

    test "mix.exs pins the 1.17.2 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:chromic_pdf, "~> 1.17.2"}|
    end

    test "companion lock is 1.17.2" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"chromic_pdf": {:hex, :chromic_pdf, "1.17.2"|
      refute lock =~ ~s|"chromic_pdf": {:hex, :chromic_pdf, "1.17.1"|
    end

    test "capture_screenshot and print_to_pdf we use still load" do
      {:module, ChromicPDF} = Code.ensure_loaded(ChromicPDF)
      assert function_exported?(ChromicPDF, :capture_screenshot, 1)
      assert function_exported?(ChromicPDF, :capture_screenshot, 2)
      assert function_exported?(ChromicPDF, :print_to_pdf, 1)
      assert function_exported?(ChromicPDF, :print_to_pdf, 2)

      {:module, ChromicPDF.CloseTarget} =
        Code.ensure_loaded(ChromicPDF.CloseTarget)

      assert function_exported?(ChromicPDF.CloseTarget, :new, 1)

      {:module, ChromicPDF.ChromeError} =
        Code.ensure_loaded(ChromicPDF.ChromeError)

      {:module, ChromicPDF.Browser.ExecutionError} =
        Code.ensure_loaded(ChromicPDF.Browser.ExecutionError)

      {:module, ChromicPDF.Browser.Channel} =
        Code.ensure_loaded(ChromicPDF.Browser.Channel)

      assert function_exported?(ChromicPDF.Browser.Channel, :run_protocol, 3)
    end
  end

  describe "1.17.2 changelog" do
    test "documents explicit disposeBrowserContext instead of disposeOnDetach" do
      changelog = File.read!(@changelog)

      v1172 =
        changelog
        |> String.split("\n## ")
        |> Enum.map(&String.replace_prefix(&1, "## ", ""))
        |> Enum.find(&String.starts_with?(&1, "[1.17.2]"))

      assert v1172
      assert v1172 =~ "CloseTarget"
      assert v1172 =~ "disposeOnDetach"
      assert v1172 =~ "orphaned Chrome"
      assert v1172 =~ "#349"
      refute v1172 =~ "Breaking"
    end
  end

  describe "1.17.2 CloseTarget disposes the private browser context" do
    test "CloseTarget detaches then disposeBrowserContext, not closeTarget" do
      source = File.read!(@close_target)

      assert source =~ ~s|"Target.detachFromTarget"|
      assert source =~ ~s|"Target.disposeBrowserContext"|
      refute source =~ ~s|"Target.closeTarget"|
      refute source =~ "disposeOnDetach"
    end

    test "SpawnSession creates a context without disposeOnDetach" do
      source = File.read!(@spawn_session)

      assert source =~ ~s|"Target.createBrowserContext"|
      assert source =~ ~s|output(["targetId", "sessionId", "browserContextId"])|
      refute source =~ "disposeOnDetach"
    end

    test "Browser stashes the channel and browserContextId for CloseTarget" do
      source = File.read!(@browser)

      assert source =~
               ~s|%{channel: channel, session_id: sid, target_id: tid, browser_context_id: bcid}|

      assert source =~ "browserContextId: bcid"
      assert source =~ "Channel.run_protocol(channel, protocol, timeout)"
    end
  end

  describe "1.17.2 graceful shutdown" do
    test "Channel traps exits so Browser.close still dispatches" do
      source = File.read!(@channel)

      assert source =~ "Process.flag(:trap_exit, true)"
      assert source =~ ~s|JsonRPC.encode({"Browser.close", %{}}, next_call_id)|
      assert source =~ "Timeout in Channel.run_protocol/3!"
    end

    test "SessionPool closes workers on shutdown instead of skipping" do
      source = File.read!(@session_pool)

      assert source =~
               "def terminate_worker(:shutdown, worker_state, pool_state) do"

      assert source =~ "pool_state.terminate_worker.(worker_state.session)"

      refute source =~
               "We do not put in the effort to clean up individual targets"
    end
  end

  describe "app ChromicPDF usage is unchanged" do
    test "TV poster capture still uses capture_screenshot html, not print_to_pdf" do
      chromic = File.read!(@chromic)

      assert chromic =~ "ChromicPDF.capture_screenshot("
      assert chromic =~ "{:html, html}"
      assert chromic =~ "full_page: true"
      assert chromic =~ "evaluate: %{expression: @wait_for_poster_ready}"
      assert chromic =~ "timeout: 30_000"
      assert chromic =~ "error in ChromicPDF.ChromeError"
      refute chromic =~ "print_to_pdf"
      refute chromic =~ "timezone:"
      refute chromic =~ "on_demand"
      refute chromic =~ "protocol:"
    end

    test "application still starts ChromicPDF from env when enabled" do
      application = File.read!(@application)
      config = File.read!(@config)
      test_config = File.read!(@test_config)

      assert application =~
               "[{ChromicPDF, Application.get_env(:ysc, ChromicPDF, [])}]"

      assert config =~ "no_sandbox: true"
      assert config =~ ~s|chrome_args: ["--disable-dev-shm-usage"]|
      assert test_config =~ "config :ysc, :chromic_pdf_enabled, false"
      refute application =~ "on_demand"
    end

    test "Sentry still discards Channel.run_protocol timeout crashes" do
      source = File.read!(@sentry_filter)

      assert source =~
               ~s|@chromic_pdf_protocol_timeout "Timeout in Channel.run_protocol/3!"|

      assert source =~ "ChromicPDF.Browser.ExecutionError"
    end
  end
end
