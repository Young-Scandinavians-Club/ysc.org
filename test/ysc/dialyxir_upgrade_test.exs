defmodule Ysc.DialyxirUpgradeTest do
  @moduledoc """
  Guards the dialyxir 1.4.8 → 1.4.9 upgrade.

  1.4.9 is a patch: `plt_add_apps` now loads the listed apps
  (`(config[:plt_add_apps] || []) |> load_apps()` — 1.4.8 piped only
  `[]` because `|>` binds tighter than `||`); `:call_with_opaque`
  unwraps OTP 28 `{position, type, type_string}` triples and drops a
  stray `}` from the message. Mix task APIs, `@dialyzer` attributes,
  and our mix.exs `plt_file` / `list_unused_filters` / `plt_add_apps`
  config are unchanged. extras: none (erlex stays 0.2.9).

  1.4.8 still applies: OTP 28 Dialyzer warnings `:exact_compare`,
  `:opaque_compare`, and `:opaque_union`; line-and-column locations
  match line-specific ignore entries. We do not use an ignore file
  (CI uses OTP 27 today; `.tool-versions` lists OTP 28).
  """
  use ExUnit.Case, async: true

  @project Path.expand("../../deps/dialyxir/lib/dialyxir/project.ex", __DIR__)
  @warnings Path.expand("../../deps/dialyxir/lib/dialyxir/warnings.ex", __DIR__)
  @call_with_opaque Path.expand(
                      "../../deps/dialyxir/lib/dialyxir/warnings/call_with_opaque.ex",
                      __DIR__
                    )
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
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
    Code.ensure_loaded!(Dialyxir.Warnings.CallWithOpaque)
    Code.ensure_loaded!(Dialyxir.Warnings.ExactCompare)
    Code.ensure_loaded!(Dialyxir.Warnings.OpaqueCompare)
    Code.ensure_loaded!(Dialyxir.Warnings.OpaqueUnion)
    Code.ensure_loaded!(Dialyxir.Warnings.ExactEquality)
    Code.ensure_loaded!(Dialyxir.Warnings.OpaqueEquality)
    Code.ensure_loaded!(Dialyxir.Warnings.OpaqueNonequality)
    :ok
  end

  describe "1.4.9 Hex lock and public APIs" do
    test "locks the Hex package to 1.4.9" do
      assert to_string(Application.spec(:dialyxir, :vsn)) == "1.4.9"
    end

    test "erlex companion lock stays on 0.2.9" do
      assert to_string(Application.spec(:erlex, :vsn)) == "0.2.9"
    end

    test "lockfile extras stay on erlex 0.2.9" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"dialyxir": {:hex, :dialyxir, "1.4.9"|
      refute lock =~ ~s|"dialyxir": {:hex, :dialyxir, "1.4.8"|
      assert lock =~ ~s|"erlex": {:hex, :erlex, "0.2.9"|
    end

    test "mix tasks we invoke still exist" do
      assert {:module, _} = Code.ensure_loaded(Mix.Tasks.Dialyzer)
      assert function_exported?(Mix.Tasks.Dialyzer, :run, 1)
      assert {:module, _} = Code.ensure_loaded(Mix.Tasks.Dialyzer.Explain)
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
      assert mix_exs =~ "plt_add_apps: [:mix, :credo, :stripity_stripe]"
    end

    test "project config still enables unused-filter listing" do
      dialyzer = Keyword.fetch!(Mix.Project.config(), :dialyzer)
      assert dialyzer[:list_unused_filters] == true
      assert dialyzer[:plt_file] == {:no_warn, "priv/plts/dialyzer.plt"}
      assert dialyzer[:plt_add_apps] == [:mix, :credo, :stripity_stripe]
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

  describe "1.4.9 plt_add_apps loading" do
    test "plt_add_apps pipes the configured list into load_apps/1" do
      source = File.read!(@project)

      assert source =~
               "defp plt_add_apps, do: (dialyzer_config()[:plt_add_apps] || []) |> load_apps()"

      refute source =~
               "defp plt_add_apps, do: dialyzer_config()[:plt_add_apps] || [] |> load_apps()"
    end

    test "load_apps/1 still calls Application.load/1 for each listed app" do
      source = File.read!(@project)
      assert source =~ "defp load_apps(nil), do: nil"
      assert source =~ "Enum.each(apps, &Application.load/1)"
    end
  end

  describe "1.4.9 call_with_opaque OTP 28 formatting" do
    test "integer positions from OTP 27 still format" do
      arguments = [
        ~c"binary",
        ~c"split",
        ~c"(_, _)",
        [2],
        [:erl_types.t_atom()]
      ]

      result = Dialyxir.Warnings.CallWithOpaque.format_long(arguments)
      assert result =~ "an opaque term in 2nd argument"
      assert result =~ "a structured term of type atom() is expected"
      refute result =~ "}}."
    end

    test "OTP 28 {position, type, type_string} triples format as positions" do
      conflicts = [{2, :erl_types.t_atom(), ~c"atom()"}]

      arguments = [
        ~c"binary",
        ~c"split",
        ~c"(_, _)",
        conflicts,
        [:erl_types.t_atom()]
      ]

      result = Dialyxir.Warnings.CallWithOpaque.format_long(arguments)
      assert result =~ "an opaque term in 2nd argument"
      assert result =~ "a structured term of type atom() is expected"
      refute result =~ "{2,"
    end

    test "several triples list ordinals and drop the stray closing brace" do
      conflicts = [
        {1, :erl_types.t_atom(), ~c"atom()"},
        {3, :erl_types.t_atom(), ~c"atom()"}
      ]

      expected = [:erl_types.t_atom(), :erl_types.t_binary()]
      arguments = [~c"binary", ~c"split", ~c"(_, _, _)", conflicts, expected]
      result = Dialyxir.Warnings.CallWithOpaque.format_long(arguments)
      assert result =~ "opaque terms in 1st and 3rd arguments"

      assert String.ends_with?(
               result,
               "terms of different types are expected in these positions."
             )

      refute result =~ "}}."
    end

    test "source unwraps triples before form_positions/1" do
      source = File.read!(@call_with_opaque)
      assert source =~ "arg_positions = Enum.map(conflicts, &position/1)"

      assert source =~
               "defp position({position, _type, _type_string}), do: position"

      assert source =~ ~S[when #{form_expected(expected_args)}.]
      refute source =~ ~S[when #{form_expected(expected_args)}}.]
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
