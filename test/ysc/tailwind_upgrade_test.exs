defmodule Ysc.TailwindUpgradeTest do
  @moduledoc """
  Guards the tailwind Mix wrapper 0.5.1 → 0.5.2 upgrade.

  0.5.2 is a patch with no documented breaking changes. GitHub's
  release redirect now sends more than 10,240 bytes of headers, the
  default `max_header_size` of httpc on OTP 27+, so `mix tailwind.install`
  failed with `{:header_too_long, {:max, 10240}}`. 0.5.2 passes
  `max_header_size: 32_768`. It also spells "override" in the
  proxy/cert error message (was "overide").

  We do not set `:path`. The wrapper still downloads into `_build`.
  Public APIs (`bin_path/1`, `run/2`, `install_and_run/2`,
  `configured_version/0`) are unchanged. The Tailwind CSS binary stays
  4.3.3. Query Console already locks 0.5.2.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @qc_mix_exs Path.expand("../../query_console/mix.exs", __DIR__)
  @qc_mix_lock Path.expand("../../query_console/mix.lock", __DIR__)
  @changelog Path.expand("../../deps/tailwind/CHANGELOG.md", __DIR__)
  @tailwind Path.expand("../../deps/tailwind/lib/tailwind.ex", __DIR__)
  @config Path.expand("../../config/config.exs", __DIR__)
  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @dev Path.expand("../../config/dev.exs", __DIR__)
  @test_config Path.expand("../../config/test.exs", __DIR__)

  setup_all do
    _ = Application.load(:tailwind)
    {:module, Tailwind} = Code.ensure_loaded(Tailwind)
    {:module, Mix.Tasks.Tailwind} = Code.ensure_loaded(Mix.Tasks.Tailwind)

    {:module, Mix.Tasks.Tailwind.Install} =
      Code.ensure_loaded(Mix.Tasks.Tailwind.Install)

    :ok
  end

  describe "0.5.2 Hex lock and public APIs" do
    test "locks the Hex package to 0.5.2" do
      assert to_string(Application.spec(:tailwind, :vsn)) == "0.5.2"
    end

    test "mix.exs pins the 0.5.2 floor" do
      mix_exs = File.read!(@mix_exs)

      assert mix_exs =~
               ~s[{:tailwind, "~> 0.5.2", runtime: Mix.env() == :dev}]

      refute mix_exs =~
               ~s[{:tailwind, "~> 0.5", runtime: Mix.env() == :dev}]
    end

    test "companion lock is 0.5.2 and extras stay put" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"tailwind": {:hex, :tailwind, "0.5.2"|
      refute lock =~ ~s|"tailwind": {:hex, :tailwind, "0.5.1"|
      assert lock =~ ~s|"ranch": {:hex, :ranch, "2.3.0"|
      refute lock =~ ~s|"ranch": {:hex, :ranch, "2.4.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
    end

    test "wrapper APIs we invoke still exist" do
      assert function_exported?(Tailwind, :bin_path, 0)
      assert function_exported?(Tailwind, :bin_path, 1)
      assert function_exported?(Tailwind, :bin_version, 0)
      assert function_exported?(Tailwind, :bin_version, 1)
      assert function_exported?(Tailwind, :configured_version, 0)
      assert function_exported?(Tailwind, :configured_version, 1)
      assert function_exported?(Tailwind, :config_for!, 1)
      assert function_exported?(Tailwind, :install, 0)
      assert function_exported?(Tailwind, :install_and_run, 2)
      assert function_exported?(Tailwind, :run, 2)
      assert function_exported?(Tailwind, :latest_version, 0)
      assert function_exported?(Mix.Tasks.Tailwind, :run, 1)
      assert function_exported?(Mix.Tasks.Tailwind.Install, :run, 1)
    end

    test "package elixir requirement is >= 1.14 which we satisfy" do
      mix_exs = File.read!(Path.expand("../../deps/tailwind/mix.exs", __DIR__))
      assert mix_exs =~ ~s(elixir: "~> 1.14")
      assert Version.match?(System.version(), "~> 1.20")
    end
  end

  describe "0.5.2 larger httpc response headers" do
    test "changelog documents the header_too_long fix" do
      changelog = File.read!(@changelog)
      assert changelog =~ "## v0.5.2 (2026-10-24)"

      assert changelog =~
               "Allow larger response headers when downloading Tailwind"

      assert changelog =~ "{:header_too_long, {:max, 10240}}"
      assert changelog =~ "OTP 27+"
      refute changelog =~ "Breaking"
    end

    test "download options raise httpc max_header_size above the OTP 27 default" do
      source = File.read!(@tailwind)

      assert source =~
               "options = [body_format: :binary, max_header_size: 32_768]"

      refute source =~ "options = [body_format: :binary]\n"

      assert 32_768 > 10_240
    end

    test "proxy error message spells override, not overide" do
      source = File.read!(@tailwind)

      assert source =~
               "your certificates are set via OTP ca certfile override via SSL configuration."

      refute source =~ "overide"
    end
  end

  describe "existing call sites" do
    test "config does not set :path and still uses Tailwind CSS 4.3.3" do
      config = File.read!(@config)
      runtime = File.read!(@runtime)
      dev = File.read!(@dev)
      test_config = File.read!(@test_config)

      refute config =~ ~r/config :tailwind,\s*:path/
      refute config =~ "MIX_TAILWIND_PATH"
      refute runtime =~ "MIX_TAILWIND_PATH"
      refute runtime =~ "config :tailwind, path:"
      refute dev =~ "config :tailwind, path:"
      refute test_config =~ "config :tailwind, path:"

      assert config =~ """
             config :tailwind,
               version: "4.3.3",
             """

      assert config =~ "admin:"
    end

    test "mix aliases still install and run default and admin" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ "tailwind.install --if-missing"
      assert mix_exs =~ ~s("tailwind default")
      assert mix_exs =~ ~s("tailwind admin")
      assert mix_exs =~ ~s("tailwind default --minify")
      assert mix_exs =~ ~s("tailwind admin --minify")
    end

    test "configured_version reads the app config default" do
      assert Tailwind.configured_version() == "4.3.3"
      assert Tailwind.configured_version(:default) == "4.3.3"
      assert Tailwind.configured_version(:admin) == "4.3.3"
      assert Tailwind.config_for!(:default)[:args]
      assert Tailwind.config_for!(:admin)[:args]
    end

    test "dev watchers still call install_and_run for default and admin" do
      dev = File.read!(@dev)

      assert dev =~
               "tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}"

      assert dev =~
               "tailwind_admin: {Tailwind, :install_and_run, [:admin, ~w(--watch)]}"
    end

    test "query_console already locks 0.5.2 and is not mixed into this bump" do
      qc_mix = File.read!(@qc_mix_exs)
      qc_lock = File.read!(@qc_mix_lock)

      assert qc_lock =~ ~s|"tailwind": {:hex, :tailwind, "0.5.2"|
      assert qc_mix =~ ~s[{:tailwind, "~> 0.3", runtime: Mix.env() == :dev}]
    end
  end
end
