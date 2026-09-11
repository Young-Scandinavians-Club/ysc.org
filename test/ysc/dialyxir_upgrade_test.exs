defmodule Ysc.DialyxirUpgradeTest do
  @moduledoc """
  Guards the dialyxir 1.4.7 → 1.4.8 upgrade.

  1.4.8 is a patch: OTP 28 Dialyzer warnings `:exact_compare`,
  `:opaque_compare`, and `:opaque_union` format instead of "Unknown
  warning"; line-and-column locations match line-specific ignore
  entries; ignore_file / ignore_file_strict docs were clarified. Mix
  task APIs, `@dialyzer` attributes, and our mix.exs `plt_file` /
  `list_unused_filters` config are unchanged. We do not use an ignore
  file (CI uses OTP 27 today; `.tool-versions` lists OTP 28).
  """
  use ExUnit.Case, async: true

  @project Path.expand("../../deps/dialyxir/lib/dialyxir/project.ex", __DIR__)
  @warnings Path.expand("../../deps/dialyxir/lib/dialyxir/warnings.ex", __DIR__)
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @ci Path.expand("../../.github/workflows/ci.yml", __DIR__)
  @tahoe_live Path.expand(
                "../../lib/ysc_web/live/tahoe_booking_live.ex",
                __DIR__
              )

  setup_all do
    _ = Application.load(:dialyxir)
    _ = Application.load(:erlex)
    Code.ensure_loaded!(Mix.Tasks.Dialyzer)
    Code.ensure_loaded!(Mix.Tasks.Dialyzer.Explain)
    Code.ensure_loaded!(Dialyxir.Warnings)
    Code.ensure_loaded!(Dialyxir.Warnings.ExactCompare)
    Code.ensure_loaded!(Dialyxir.Warnings.OpaqueCompare)
    Code.ensure_loaded!(Dialyxir.Warnings.OpaqueUnion)
    Code.ensure_loaded!(Dialyxir.Warnings.ExactEquality)
    Code.ensure_loaded!(Dialyxir.Warnings.OpaqueEquality)
    Code.ensure_loaded!(Dialyxir.Warnings.OpaqueNonequality)
    :ok
  end

  describe "1.4.8 Hex lock and public APIs" do
    test "locks the Hex package to 1.4.8" do
      assert to_string(Application.spec(:dialyxir, :vsn)) == "1.4.8"
    end

    test "erlex companion lock stays on 0.2.9" do
      assert to_string(Application.spec(:erlex, :vsn)) == "0.2.9"
    end

    test "mix tasks we invoke still exist" do
      assert function_exported?(Mix.Tasks.Dialyzer, :run, 1)
      assert function_exported?(Mix.Tasks.Dialyzer.Explain, :run, 1)
    end

    test "package elixir requirement is >= 1.6.0 which we satisfy" do
      mix_exs = File.read!(Path.expand("../../deps/dialyxir/mix.exs", __DIR__))
      assert mix_exs =~ ~s(elixir: ">= 1.6.0")
      assert Version.match?(System.version(), "~> 1.20")
    end
  end

  describe "mix.exs and CI still use the same Dialyzer surface" do
    test "constraint stays ~> 1.4 and list_unused_filters remains on" do
      mix_exs = File.read!(@mix_exs)

      assert mix_exs =~
               ~s({:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false})

      assert mix_exs =~ "list_unused_filters: true"
      assert mix_exs =~ ~s(plt_file: {:no_warn, "priv/plts/dialyzer.plt"})
    end

    test "project config still enables unused-filter listing" do
      dialyzer = Keyword.fetch!(Mix.Project.config(), :dialyzer)
      assert dialyzer[:list_unused_filters] == true
      assert dialyzer[:plt_file] == {:no_warn, "priv/plts/dialyzer.plt"}
      refute Keyword.has_key?(dialyzer, :ignore_warnings)
    end

    test "does not ship a Dialyxir ignore file" do
      refute File.exists?(Path.expand("../../.dialyzer_ignore.exs", __DIR__))

      refute File.exists?(
               Path.expand("../../dialyzer.ignore-warnings", __DIR__)
             )
    end

    test "CI still runs mix dialyzer after building the PLT" do
      ci = File.read!(@ci)
      assert ci =~ "mix dialyzer --plt"
      assert ci =~ "mix dialyzer"
    end

    test "app code still uses @dialyzer attributes" do
      tahoe = File.read!(@tahoe_live)

      assert tahoe =~
               "@dialyzer {:nowarn_function, validate_and_create_booking: 1}"

      assert tahoe =~ "@dialyzer :no_match"
    end
  end

  describe "1.4.8 OTP 28 warning modules" do
    test "warnings map includes exact_compare, opaque_compare, and opaque_union" do
      warnings = Dialyxir.Warnings.warnings()

      assert warnings[:exact_compare] == Dialyxir.Warnings.ExactCompare
      assert warnings[:opaque_compare] == Dialyxir.Warnings.OpaqueCompare
      assert warnings[:opaque_union] == Dialyxir.Warnings.OpaqueUnion
    end

    test "OTP 26/27 warning modules remain for backward compatibility" do
      warnings = Dialyxir.Warnings.warnings()

      assert warnings[:exact_eq] == Dialyxir.Warnings.ExactEquality
      assert warnings[:opaque_eq] == Dialyxir.Warnings.OpaqueEquality
      assert warnings[:opaque_neq] == Dialyxir.Warnings.OpaqueNonequality
    end

    test "ExactCompare formats equality that can never be true" do
      message =
        Dialyxir.Warnings.ExactCompare.format_long(["atom()", "==", "pid()"])

      assert message =~ "can never evaluate to 'true'"
      assert message =~ "=="
    end

    test "OpaqueCompare maps == to equality and =/= to inequality" do
      equality =
        Dialyxir.Warnings.OpaqueCompare.format_short(["atom()", "==", "term()"])

      inequality =
        Dialyxir.Warnings.OpaqueCompare.format_short(["atom()", "/=", "term()"])

      assert equality =~ "equality"
      assert inequality =~ "inequality"
    end

    test "OpaqueUnion formats both opaque and non-opaque clause bodies" do
      opaque = Dialyxir.Warnings.OpaqueUnion.format_long([true, "term()"])
      broken = Dialyxir.Warnings.OpaqueUnion.format_long([false, "atom()"])

      assert opaque =~ "opacity is broken by the other clauses"
      assert broken =~ "violates the opacity of the other clauses"
    end

    test "warnings.ex lists the three OTP 28 modules next to the legacy ones" do
      source = File.read!(@warnings)
      assert source =~ "Dialyxir.Warnings.ExactCompare"
      assert source =~ "Dialyxir.Warnings.ExactEquality"
      assert source =~ "Dialyxir.Warnings.OpaqueCompare"
      assert source =~ "Dialyxir.Warnings.OpaqueEquality"
      assert source =~ "Dialyxir.Warnings.OpaqueUnion"
    end
  end

  describe "1.4.8 line-and-column ignore matching" do
    test "filter_warning? unwraps {line, column} before skip?/2" do
      source = File.read!(@project)

      assert source =~ "{_, {file, line_col}, {warning_type, args}} = warning"
      assert source =~ "{line, _} -> line"
      assert source =~ "_ -> line_col"
    end
  end
end
