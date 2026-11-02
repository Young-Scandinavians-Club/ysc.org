defmodule QueryConsole.JsvUpgradeTest do
  @moduledoc """
  Guards the jsv 0.26.1 → 0.26.2 upgrade.

  0.26.2 is a patch for EEF-CVE-2026-117680 (LOW / CVE-2026-117680 /
  GHSA-cvmg-hgv6-jqcp). `JSV.Helpers.RegexExt.bounded_match?/2` now
  passes `:report_errors` to `:re.run/3` so a PCRE match-limit miss is
  not reported as `:nomatch`. Exhaustion throws
  `{JSV.Helpers.RegexExt, :budget_exhausted}`; vocabulary code turns
  that into a `JSV.ValidationError` of kind `:indeterminate_pattern`,
  which combinators cannot invert. Data that matches a `pattern` or
  `patternProperties` regex only after heavy backtracking is always
  rejected instead of skipping the subschema or passing a
  `not: {pattern: ...}` deny-list.

  `minLength` / `maxLength` now count Unicode code points, not grapheme
  clusters. Query Console does not call JSV; ReqLLM.Schema.validate/2
  uses `JSV.build!/1` + `JSV.validate/2` for JSON-schema tool args.
  req_llm lists jsv `~> 0.11`, so mix.exs keeps an override pin.
  """
  use ExUnit.Case, async: true

  alias JSV.Helpers.RegexExt
  alias JSV.ValidationError

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/jsv/CHANGELOG.md", __DIR__)
  @regex_ext Path.expand("../../deps/jsv/lib/jsv/helpers/regex_ext.ex", __DIR__)
  @validation Path.expand(
                "../../deps/jsv/lib/jsv/vocabulary/v202012/validation.ex",
                __DIR__
              )
  @applicator Path.expand(
                "../../deps/jsv/lib/jsv/vocabulary/v202012/applicator.ex",
                __DIR__
              )
  @schema_src Path.expand("../../deps/req_llm/lib/req_llm/schema.ex", __DIR__)

  # CVE-2026-117680 advisory pattern: first alternative backtracks
  # catastrophically; the second alternative matches `a+!`.
  @advisory_pattern "^(?:(a+)+b|a+!)$"
  @long_match String.duplicate("a", 20) <> "!"
  @short_match "aaa!"

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jsv)
    {:ok, _} = Application.ensure_all_started(:req_llm)
    {:module, JSV} = Code.ensure_loaded(JSV)
    {:module, RegexExt} = Code.ensure_loaded(RegexExt)
    {:module, ValidationError} = Code.ensure_loaded(ValidationError)
    {:module, ReqLLM.Schema} = Code.ensure_loaded(ReqLLM.Schema)
    :ok
  end

  describe "0.26.2 Hex lock and public APIs" do
    test "locks the Hex package to 0.26.2" do
      {:module, _} = Code.ensure_loaded(JSV)
      assert to_string(Application.spec(:jsv, :vsn)) == "0.26.2"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:jsv, "~> 0.26.2", override: true})
    end

    test "companion locks stay req_llm 1.29.0 and lotus 1.3.2" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"jsv": {:hex, :jsv, "0.26.2"|
      refute lock =~ ~s|"jsv": {:hex, :jsv, "0.26.1"|
      assert lock =~ ~s|"req_llm": {:hex, :req_llm, "1.29.0"|
      assert lock =~ ~s|"lotus": {:hex, :lotus, "1.3.2"|
      assert lock =~ ~s|"lotus_web": {:hex, :lotus_web, "1.4.0"|
      assert lock =~ ~s|"texture": {:hex, :texture, "2.0.0"|
      assert lock =~ ~s|"abnf_parsec": {:hex, :abnf_parsec, "2.1.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.1.0"|
    end

    test "build/validate APIs ReqLLM uses still exist" do
      {:module, JSV} = Code.ensure_loaded(JSV)
      {:module, ReqLLM.Schema} = Code.ensure_loaded(ReqLLM.Schema)

      assert function_exported?(JSV, :build!, 1)
      assert function_exported?(JSV, :build!, 2)
      assert function_exported?(JSV, :validate, 2)
      assert function_exported?(JSV, :validate, 3)
      assert function_exported?(JSV, :normalize_error, 1)
      assert function_exported?(ReqLLM.Schema, :validate, 2)
      assert function_exported?(RegexExt, :bounded_match?, 2)
    end

    test "ReqLLM still validates JSON-schema maps through JSV" do
      schema_src = File.read!(@schema_src)
      assert schema_src =~ "JSV.validate(data, root)"
      assert schema_src =~ "JSV.build!(schema)"
      assert schema_src =~ "JSV.normalize_error(validation_error)"

      schema = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}},
        "required" => ["name"]
      }

      assert {:ok, %{"name" => "Alice"}} =
               ReqLLM.Schema.validate(%{"name" => "Alice"}, schema)

      assert {:error, %ReqLLM.Error.Validation.Error{tag: :json_schema_validation_failed}} =
               ReqLLM.Schema.validate(%{"name" => 1}, schema)
    end
  end

  describe "0.26.2 changelog" do
    test "documents CVE-2026-117680 and code-point lengths" do
      changelog = File.read!(@changelog)

      v0262 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[0.26.2]"))

      assert v0262
      refute v0262 =~ "Breaking"
      assert v0262 =~ "CVE-2026-117680"
      assert v0262 =~ "indeterminate_pattern"
      assert v0262 =~ "code points"
    end
  end

  describe "EEF-CVE-2026-117680 regex budget exhaustion" do
    test "source reports match-limit errors instead of treating them as nomatch" do
      source = File.read!(@regex_ext)
      assert source =~ ":report_errors"
      assert source =~ "throw({__MODULE__, :budget_exhausted})"
      assert source =~ "{:error, reason} when reason in [:match_limit, :match_limit_recursion]"
    end

    test "pattern and patternProperties catch budget exhaustion as indeterminate" do
      validation = File.read!(@validation)
      applicator = File.read!(@applicator)

      assert validation =~ "{RegexExt, :budget_exhausted}"
      assert validation =~ "throw_indeterminate(vctx, :indeterminate_pattern"
      assert applicator =~ "{RegexExt, :budget_exhausted}"
      assert applicator =~ "throw_indeterminate(vctx, :indeterminate_pattern"
    end

    test "bounded_match? throws when the advisory pattern exhausts its budget" do
      {:ok, re} = Regex.compile(@advisory_pattern)

      assert catch_throw(RegexExt.bounded_match?(re, @long_match)) ==
               {RegexExt, :budget_exhausted}
    end

    test "bounded_match? still matches a short subject that does not exhaust" do
      {:ok, re} = Regex.compile(@advisory_pattern)
      assert RegexExt.bounded_match?(re, @short_match)
    end

    test "patternProperties no longer skip the subschema on budget exhaustion" do
      root =
        JSV.build!(%{
          "type" => "object",
          "patternProperties" => %{
            @advisory_pattern => %{"type" => "integer"}
          }
        })

      assert {:error, %ValidationError{errors: errors}} =
               JSV.validate(%{@long_match => "not an int"}, root)

      assert Enum.any?(errors, &(&1.kind == :indeterminate_pattern))
    end

    test "not/pattern deny-list no longer accepts a budget-exhausted match" do
      root = JSV.build!(%{"not" => %{"pattern" => @advisory_pattern}})

      assert {:error, %ValidationError{errors: errors}} =
               JSV.validate(@long_match, root)

      assert Enum.any?(errors, &(&1.kind == :indeterminate_pattern))
    end

    test "a short matching key is still type-checked by patternProperties" do
      root =
        JSV.build!(%{
          "type" => "object",
          "patternProperties" => %{
            @advisory_pattern => %{"type" => "integer"}
          }
        })

      assert {:error, %ValidationError{}} =
               JSV.validate(%{@short_match => "not an int"}, root)

      assert {:ok, _} = JSV.validate(%{@short_match => 1}, root)
    end
  end

  describe "minLength and maxLength count code points" do
    test "combining-acute e is length 2, so maxLength 1 rejects it" do
      # "é" as `e` + U+0301 is one grapheme and two code points.
      combining = "e\u0301"
      assert String.length(combining) == 1
      assert length(String.to_charlist(combining)) == 2

      root = JSV.build!(%{"maxLength" => 1})
      assert {:error, %ValidationError{errors: errors}} = JSV.validate(combining, root)
      assert Enum.any?(errors, &(&1.kind == :maxLength))
    end

    test "precomposed e-acute still has maxLength 1" do
      root = JSV.build!(%{"maxLength" => 1})
      assert {:ok, "é"} = JSV.validate("é", root)
    end
  end

  describe "Query Console usage" do
    test "app code does not call JSV" do
      lib_files = Path.wildcard(Path.expand("../../lib/**/*.{ex,heex}", __DIR__))

      refute Enum.any?(lib_files, fn path ->
               contents = File.read!(path)
               String.contains?(contents, "JSV.") or String.contains?(contents, "JSV ")
             end)
    end
  end
end
