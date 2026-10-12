defmodule Ysc.SobelowUpgradeTest do
  @moduledoc """
  Guards the sobelow 0.15.0 → 0.16.0 upgrade.

  0.16.0 is a minor. XSS.Raw now scans HEEx files and inline `~H` sigils
  (and ignores a benign local `raw/1`). XSS.SendResp follows
  `put_resp_content_type` / `put_resp_header("content-type", ...)`. New
  CLI flags: `--include-mix-tasks`, `--include-scripts`, `--summary`,
  and `--format github`. Check names, finding types, existing CLI flags
  (`--skip`, `--exit`), JSON fields, and skip fingerprints are
  unchanged. Elixir floor stays `~> 1.12`.

  A bare `--exit` now means `--exit low` and overrides `.sobelow-conf`.
  CI / preflight pass `--exit high` so the committed fail-on-high gate
  stays. New LOW HEEx `raw/1` findings (sanitized or generated HTML)
  do not fail that gate. We do not pass `--include-mix-tasks` or
  `--include-scripts`.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/sobelow/CHANGELOG.md", __DIR__)
  @sobelow_mix Path.expand("../../deps/sobelow/mix.exs", __DIR__)
  @task_src Path.expand("../../deps/sobelow/lib/mix/tasks/sobelow.ex", __DIR__)
  @raw_src Path.expand("../../deps/sobelow/lib/sobelow/xss/raw.ex", __DIR__)
  @send_resp_src Path.expand(
                   "../../deps/sobelow/lib/sobelow/xss/send_resp.ex",
                   __DIR__
                 )
  @heex_src Path.expand("../../deps/sobelow/lib/sobelow/heex.ex", __DIR__)
  @template_src Path.expand(
                  "../../deps/sobelow/lib/sobelow/parse/template.ex",
                  __DIR__
                )
  @conf Path.expand("../../.sobelow-conf", __DIR__)
  @ci Path.expand("../../.github/workflows/ci.yml", __DIR__)
  @deploy Path.expand("../../.github/workflows/fly-deploy.yml", __DIR__)
  @preflight Path.expand("../../etc/scripts/preflight.sh", __DIR__)
  @preflight_parallel Path.expand(
                        "../../etc/scripts/preflight_parallel.sh",
                        __DIR__
                      )
  @samples Path.expand(
             "../../lib/ysc_web/dev/notification_samples.ex",
             __DIR__
           )
  @preview Path.expand(
             "../../lib/ysc_web/controllers/dev_email_preview_controller.ex",
             __DIR__
           )

  setup_all do
    _ = Application.load(:sobelow)
    {:module, _} = Code.ensure_loaded(Mix.Tasks.Sobelow)
    {:module, _} = Code.ensure_loaded(Sobelow)
    {:module, _} = Code.ensure_loaded(Sobelow.Parse)
    {:module, _} = Code.ensure_loaded(Sobelow.FindingLog)
    {:module, _} = Code.ensure_loaded(Sobelow.XSS.Raw)
    {:module, _} = Code.ensure_loaded(Sobelow.XSS.SendResp)
    {:module, _} = Code.ensure_loaded(Sobelow.HEEx)
    :ok
  end

  describe "0.16.0 Hex lock and public APIs" do
    test "locks the Hex package to 0.16.0" do
      assert to_string(Application.spec(:sobelow, :vsn)) == "0.16.0"
    end

    test "mix.exs pins the 0.16.0 floor" do
      mix_exs = File.read!(@mix_exs)

      assert mix_exs =~
               ~s({:sobelow, "~> 0.16.0", only: [:dev, :test], runtime: false})
    end

    test "companion lock is 0.16.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"sobelow": {:hex, :sobelow, "0.16.0"|
      refute lock =~ ~s|"sobelow": {:hex, :sobelow, "0.15.0"|
    end

    test "mix task we invoke still exists" do
      assert {:module, _} = Code.ensure_loaded(Mix.Tasks.Sobelow)
      assert function_exported?(Mix.Tasks.Sobelow, :run, 1)
    end

    test "Sobelow and Parse entry points still load" do
      assert function_exported?(Sobelow, :run, 0)
      assert function_exported?(Sobelow.Parse, :get_fun_vars_and_meta, 4)
      assert function_exported?(Sobelow.FindingLog, :github, 0)
      assert function_exported?(Sobelow.XSS.Raw, :run, 4)
      assert function_exported?(Sobelow.XSS.SendResp, :run, 2)
    end

    test "package elixir requirement is ~> 1.12 which we satisfy" do
      mix_exs = File.read!(@sobelow_mix)
      assert mix_exs =~ ~s(elixir: "~> 1.12")
      assert Version.match?(System.version(), "~> 1.20")
    end
  end

  describe "0.16.0 changelog" do
    test "v0.16.0 section has no Elixir API breaks and keeps the CLI contract" do
      section = changelog_section(File.read!(@changelog), "v0.16.0")
      assert section != ""
      refute section =~ ~r/breaking/i

      assert section =~ "Existing check names, finding types, CLI flags"
      assert section =~ "minimum supported Elixir version remains `~> 1.12`"
      assert section =~ "HEEx files and inline `~H` sigils"
      assert section =~ "`github` output format"
      assert section =~ "`--include-mix-tasks`"
    end
  end

  describe "0.16.0 HEEx, SendResp, and CLI surface" do
    test "XSS.Raw parses inline ~H and .heex templates" do
      raw = File.read!(@raw_src)
      assert raw =~ "def parse_raw_def(fun, file \\\\ \"inline HEEx\")"
      assert raw =~ "Parse.get_heex_raw_funs(file)"
      assert raw =~ ~s(extension <- ["eex", "heex"])

      template = File.read!(@template_src)

      assert template =~
               "{:sigil_H, meta, [{:<<>>, literal_meta, [source]}, _]}"

      heex = File.read!(@heex_src)
      assert heex =~ "phx-no-curly-interpolation"
    end

    test "XSS.SendResp recognizes put_resp_content_type and content-type headers" do
      source = File.read!(@send_resp_src)
      assert source =~ "@setters [:put_resp_content_type, :put_resp_header]"

      assert source =~
               ~s|defp header_content_type_arg([_conn, "content-type", type])|
    end

    test "mix task documents github format and new opt-in path flags" do
      source = File.read!(@task_src)
      assert source =~ "include_mix_tasks: :boolean"
      assert source =~ "include_scripts: :boolean"
      assert source =~ "summary: :boolean"
      assert source =~ ~s("github")
      assert source =~ "* Config.CSRFRoute"
      assert source =~ "skip: :boolean"
      assert source =~ "exit: :string"
    end
  end

  describe "CI still uses skip plus the committed high exit gate" do
    test ".sobelow-conf still exits on high and ignores the same checks" do
      conf = File.read!(@conf)
      assert conf =~ ~s(exit: "high")
      assert conf =~ ~s(threshold: "low")
      assert conf =~ ~s("Config.CSRF")
      assert conf =~ ~s("Config.CSP")
      assert conf =~ ~s("Config.HTTPS")
      assert conf =~ ~s("DOS.StringToAtom")
    end

    test "CI, deploy, and preflight pass --skip --exit high" do
      expected = "mix sobelow --skip --exit high"
      assert File.read!(@ci) =~ expected
      assert File.read!(@deploy) =~ expected
      assert File.read!(@preflight) =~ expected
      assert File.read!(@preflight_parallel) =~ expected
    end

    test "dev email preview still skips XSS.Raw on Phoenix.HTML.raw/1" do
      samples = File.read!(@samples)
      assert samples =~ ~s(# sobelow_skip ["XSS.Raw"])
      assert samples =~ "Phoenix.HTML.raw(html)"

      preview = File.read!(@preview)
      assert preview =~ ~s(# sobelow_skip ["XSS.Raw"])
      assert preview =~ "Phoenix.HTML.raw(html)"
    end
  end

  defp changelog_section(changelog, version) do
    changelog
    |> String.split("\n## ")
    |> Enum.find("", &String.starts_with?(&1, version))
  end
end
