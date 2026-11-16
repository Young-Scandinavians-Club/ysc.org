defmodule Ysc.EsbuildUpgradeTest do
  @moduledoc """
  Guards the esbuild Mix wrapper 0.10.0 → 0.10.1 upgrade.

  0.10.1 is a patch with no documented breaking changes. `bin_path/0`
  used to call `target/0` before checking `config :esbuild, :path`, so
  start raised on an architecture without an esbuild build even when
  `MIX_ESBUILD_PATH` (or `:path`) pointed at a working executable.
  0.10.1 only computes the target for the default `_build` path.

  We do not set `:path`. The wrapper still downloads into `_build`.
  Public APIs (`bin_path/0`, `run/2`, `install_and_run/2`,
  `configured_version/0`) are unchanged. The npm esbuild binary stays
  0.17.11. NODE_PATH is a string, so the 0.10.0 list-join is unused.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/esbuild/CHANGELOG.md", __DIR__)
  @esbuild Path.expand("../../deps/esbuild/lib/esbuild.ex", __DIR__)
  @config Path.expand("../../config/config.exs", __DIR__)
  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @dev Path.expand("../../config/dev.exs", __DIR__)
  @test_config Path.expand("../../config/test.exs", __DIR__)

  setup_all do
    _ = Application.load(:esbuild)
    {:module, Esbuild} = Code.ensure_loaded(Esbuild)
    {:module, Mix.Tasks.Esbuild} = Code.ensure_loaded(Mix.Tasks.Esbuild)
    :ok
  end

  describe "0.10.1 Hex lock and public APIs" do
    test "locks the Hex package to 0.10.1" do
      assert to_string(Application.spec(:esbuild, :vsn)) == "0.10.1"
    end

    test "mix.exs pins the 0.10.1 floor" do
      mix_exs = File.read!(@mix_exs)

      assert mix_exs =~
               ~s[{:esbuild, "~> 0.10.1", runtime: Mix.env() == :dev}]

      refute mix_exs =~ ~s[{:esbuild, "~> 0.10", runtime: Mix.env() == :dev}]
    end

    test "companion lock is 0.10.1 and extras stay put" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"esbuild": {:hex, :esbuild, "0.10.1"|
      refute lock =~ ~s|"esbuild": {:hex, :esbuild, "0.10.0"|
      assert lock =~ ~s|"ranch": {:hex, :ranch, "2.3.0"|
      refute lock =~ ~s|"ranch": {:hex, :ranch, "2.4.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
    end

    test "wrapper APIs we invoke still exist" do
      assert function_exported?(Esbuild, :bin_path, 0)
      assert function_exported?(Esbuild, :bin_version, 0)
      assert function_exported?(Esbuild, :configured_version, 0)
      assert function_exported?(Esbuild, :config_for!, 1)
      assert function_exported?(Esbuild, :install, 0)
      assert function_exported?(Esbuild, :install_and_run, 2)
      assert function_exported?(Esbuild, :run, 2)
      assert function_exported?(Esbuild, :latest_version, 0)
      assert function_exported?(Mix.Tasks.Esbuild, :run, 1)
    end

    test "package elixir requirement is >= 1.14 which we satisfy" do
      mix_exs = File.read!(Path.expand("../../deps/esbuild/mix.exs", __DIR__))
      assert mix_exs =~ ~s(elixir: "~> 1.14")
      assert Version.match?(System.version(), "~> 1.20")
    end
  end

  describe "0.10.1 skip target when :path is set" do
    test "changelog documents the path-before-target fix" do
      changelog = File.read!(@changelog)
      assert changelog =~ "## v0.10.1 (2026-10-19)"

      assert changelog =~
               "Don't try to compute the target if a `:path` is configured"
    end

    test "bin_path reads :path before computing the default target path" do
      source = File.read!(@esbuild)

      assert source =~ """
               def bin_path do
                 Application.get_env(:esbuild, :path) || default_bin_path()
               end
             """

      assert source =~ "defp default_bin_path do"
      assert source =~ ~S[name = "esbuild-#{target()}"]
    end

    test "bin_path returns a configured :path without needing the binary" do
      previous = Application.get_env(:esbuild, :path)

      fake =
        "/tmp/ysc-esbuild-upgrade-#{System.unique_integer([:positive])}"

      try do
        Application.put_env(:esbuild, :path, fake)
        assert Esbuild.bin_path() == fake
      after
        if previous do
          Application.put_env(:esbuild, :path, previous)
        else
          Application.delete_env(:esbuild, :path)
        end
      end
    end
  end

  describe "existing call sites" do
    test "config does not set :path and still uses npm esbuild 0.17.11" do
      config = File.read!(@config)
      runtime = File.read!(@runtime)
      dev = File.read!(@dev)
      test_config = File.read!(@test_config)

      refute config =~ ~r/config :esbuild,\s*:path/
      refute config =~ "MIX_ESBUILD_PATH"
      refute runtime =~ "MIX_ESBUILD_PATH"
      refute runtime =~ "config :esbuild, path:"
      refute dev =~ "config :esbuild, path:"
      refute test_config =~ "config :esbuild, path:"

      assert config =~ """
             config :esbuild,
               version: "0.17.11",
             """

      assert config =~ "html5_qrcode:"

      assert config =~
               ~S[env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}]
    end

    test "mix aliases still install and run default, admin, and html5_qrcode" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ "esbuild.install --if-missing"
      assert mix_exs =~ ~s("esbuild default")
      assert mix_exs =~ ~s("esbuild admin")
      assert mix_exs =~ ~s("esbuild html5_qrcode")
      assert mix_exs =~ ~s("esbuild default --minify")
      assert mix_exs =~ ~s("esbuild admin --minify")
    end

    test "configured_version reads the app config default" do
      assert Esbuild.configured_version() == "0.17.11"
      assert Esbuild.config_for!(:default)[:args]
      assert Esbuild.config_for!(:admin)[:args]
      assert Esbuild.config_for!(:html5_qrcode)[:args]
    end
  end
end
