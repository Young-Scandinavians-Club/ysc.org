defmodule Ysc.ExCldrNumbersUpgradeTest do
  @moduledoc """
  Guards the ex_cldr_numbers 2.38.3 → 2.38.5 upgrade.

  2.38.4/2.38.5 are patches. Public `Cldr.Number.to_string/3` APIs are
  unchanged. They:

  * Take the sign from each number formatted with a validated options
    struct, so ranges that cross zero no longer copy the first sign
    (2.38.4, #65)
  * Use CLDR currency separators where a locale has them (`fr-CH`,
    `de-AT`); we only compile `:en` (2.38.4, #66)
  * Put the locale's approximately sign where the minus goes in
    `to_approx_string/3`; we do not call it (2.38.4, #67)
  * Prefix the minus to the whole pattern when a format has no
    negative subpattern (TR35): `en` formats -2 EUR as "-€2.00", not
    "€-2.00", and :en USD as "-$2.00", not "$-2.00" (2.38.5, #68)
  * Stop looping on quoted literals; uncompilable formats and more
    than four currency signs return errors, not exceptions (2.38.5)
  * Format scientific `Decimal`/zero without raising; needs
    `cldr_utils` 2.29.8 (2.38.5)

  We format money via `Money.to_string` (ex_money → Cldr.Number) in
  `:en` only. `Ysc.MoneyHelper.format_money/1` still rewrites leftover
  `"$-"` to `"-$"`. extras: cldr_utils 2.29.8 (required). castore
  1.0.21 / telemetry 1.4.2 / phoenix_template 1.0.4 restored.
  """
  use ExUnit.Case, async: true

  alias Cldr.Number.Format.Compiler
  alias Ysc.MoneyHelper

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/ex_cldr_numbers/CHANGELOG.md", __DIR__)
  @package_mix Path.expand("../../deps/ex_cldr_numbers/mix.exs", __DIR__)
  @parser Path.expand(
            "../../deps/ex_cldr_numbers/src/decimal_formats_parser.yrl",
            __DIR__
          )
  @lexer Path.expand(
           "../../deps/ex_cldr_numbers/src/decimal_formats_lexer.xrl",
           __DIR__
         )
  @utils_math Path.expand(
                "../../deps/cldr_utils/lib/cldr/utils/math.ex",
                __DIR__
              )
  @cldr Path.expand("../../lib/ysc/cldr.ex", __DIR__)
  @money_helper Path.expand("../../lib/ysc/money_helpers.ex", __DIR__)
  @config_exs Path.expand("../../config/config.exs", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ex_cldr_numbers)
    {:ok, _} = Application.ensure_all_started(:ex_money)
    {:module, Cldr.Number} = Code.ensure_loaded(Cldr.Number)
    {:module, Compiler} = Code.ensure_loaded(Compiler)
    {:module, Ysc.Cldr} = Code.ensure_loaded(Ysc.Cldr)
    {:module, Ysc.Cldr.Number} = Code.ensure_loaded(Ysc.Cldr.Number)
    {:module, Cldr.Math} = Code.ensure_loaded(Cldr.Math)
    :ok
  end

  describe "2.38.5 Hex lock and public APIs" do
    test "locks the Hex package to 2.38.5" do
      assert to_string(Application.spec(:ex_cldr_numbers, :vsn)) ==
               "2.38.5"
    end

    test "mix.exs pins the 2.38.5 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:ex_cldr_numbers, "~> 2.38.5"}|
      refute mix_exs =~ ~s|{:ex_cldr_numbers, "~> 2.38"}|
    end

    test "companion lock is 2.38.5 and extras stay put" do
      lock = File.read!(@mix_lock)

      assert lock =~
               ~s|"ex_cldr_numbers": {:hex, :ex_cldr_numbers, "2.38.5"|

      refute lock =~
               ~s|"ex_cldr_numbers": {:hex, :ex_cldr_numbers, "2.38.3"|

      refute lock =~
               ~s|"ex_cldr_numbers": {:hex, :ex_cldr_numbers, "2.38.4"|

      assert lock =~ ~s|"cldr_utils": {:hex, :cldr_utils, "2.29.8"|
      refute lock =~ ~s|"cldr_utils": {:hex, :cldr_utils, "2.29.7"|
      assert lock =~ ~s|"castore": {:hex, :castore, "1.0.21"|
      refute lock =~ ~s|"castore": {:hex, :castore, "1.0.22"|
      assert lock =~ ~s|"telemetry": {:hex, :telemetry, "1.4.2"|

      assert lock =~
               ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|

      assert lock =~
               ~s|"digital_token": {:hex, :digital_token, "1.0.0"|
    end

    test "to_string APIs we would call still exist" do
      assert function_exported?(Cldr.Number, :to_string, 1)
      assert function_exported?(Cldr.Number, :to_string, 2)
      assert function_exported?(Cldr.Number, :to_string, 3)
      assert function_exported?(Cldr.Number, :to_string!, 1)
      assert function_exported?(Cldr.Number, :to_string!, 2)
      assert function_exported?(Cldr.Number, :to_string!, 3)
      assert function_exported?(Cldr.Number, :to_approx_string, 1)
      assert function_exported?(Cldr.Number, :to_approx_string, 2)
      assert function_exported?(Cldr.Number, :to_approx_string, 3)
      assert function_exported?(Cldr.Number, :to_range_string, 1)
      assert function_exported?(Cldr.Number, :to_range_string, 2)
      assert function_exported?(Cldr.Number, :to_range_string, 3)
      assert function_exported?(Ysc.Cldr.Number, :to_string, 1)
      assert function_exported?(Ysc.Cldr.Number, :to_string, 2)
    end

    test "package elixir requirement is still 1.12 which we satisfy" do
      mix_exs = File.read!(@package_mix)
      assert mix_exs =~ ~s(elixir: "~> 1.12")
      assert mix_exs =~ ~s|{:cldr_utils, "~> 2.29 and >= 2.29.8"}|
      assert Version.match?(System.version(), "~> 1.12")
    end
  end

  describe "2.38.5 docs and source" do
    test "changelog documents 2.38.5 minus prefix and 2.38.4 sign/separators" do
      changelog = File.read!(@changelog)
      sections = String.split(changelog, "\n## ")

      latest =
        Enum.find(sections, &String.starts_with?(&1, "Cldr Numbers v2.38.5"))

      previous =
        Enum.find(sections, &String.starts_with?(&1, "Cldr Numbers v2.38.4"))

      assert latest
      assert latest =~ "minus sign in front of the whole pattern"
      assert latest =~ "-€2.00"
      assert latest =~ "€-2.00"
      assert latest =~ "quoted literal"
      assert latest =~ "`cldr_utils` 2.29.8"
      assert previous
      assert previous =~ "sign from each number"
      assert previous =~ "-5..5"
      assert previous =~ "fr-CH"
      assert previous =~ "to_approx_string/3"
    end

    test "parser prefixes minus to the whole positive subpattern" do
      source = File.read!(@parser)

      assert source =~
               "Per TR35 it is the minus sign prefixed to the whole positive"

      assert source =~ ~s({negative, [{minus, "-"} | Positive]})
    end

    test "lexer quoted strings consume more than one character" do
      source = File.read!(@lexer)
      assert source =~ "QuotedString"
      assert source =~ "unquote(TokenChars)"
      assert source =~ "a currency symbol is one to four currency signs"
    end

    test "cldr_utils 2.29.8 returns Decimal zeros unchanged" do
      source = File.read!(@utils_math)

      assert source =~
               "def round_significant(%Decimal{} = number, n) when n <= 0 do"

      assert source =~
               "def round_significant(%Decimal{coef: coef} = number, _n) when coef == 0 or is_atom(coef) do"

      assert to_string(Application.spec(:cldr_utils, :vsn)) == "2.29.8"
    end
  end

  describe "2.38.5 formats :en currency with the minus in front" do
    test "Cldr.Number formats negative EUR as -€ not €-" do
      assert {:ok, formatted} =
               Cldr.Number.to_string(-2, Ysc.Cldr,
                 locale: :en,
                 currency: :EUR,
                 fractional_digits: 2
               )

      assert formatted == "-€2.00"
      refute formatted == "€-2.00"
    end

    test "Money.to_string formats negative USD as -$ not $-" do
      money = Money.new(:USD, "-123.00")
      assert Money.to_string!(money) == "-$123.00"
      refute Money.to_string!(money) == "$-123.00"

      assert {:ok, "-$123.00"} =
               Money.to_string(money,
                 separator: ".",
                 delimiter: ",",
                 fractional_digits: 2
               )
    end

    test "MoneyHelper still displays negatives as -$123.00" do
      money = Money.new(:USD, "-123.00")
      assert {:ok, "-$123.00"} = MoneyHelper.format_money(money)
      assert MoneyHelper.format_money!(money) == "-$123.00"
      assert MoneyHelper.format_money_safe(money) == "-$123.00"
    end

    test "positive USD formatting is unchanged" do
      assert Money.to_string!(Money.new(:USD, "10.99")) == "$10.99"

      assert {:ok, "$1,000.00"} =
               MoneyHelper.format_money(Money.new(:USD, "1000.00"))
    end

    test "implicit negative currency parse puts minus before the symbol" do
      assert {:ok, parsed} = Compiler.parse("¤#,##0.00")
      assert parsed[:negative][:minus] == ~c"-"
      assert hd(parsed[:negative]) == {:minus, ~c"-"}
      assert Keyword.get(parsed[:negative], :currency) == 1
    end

    test "quoted multi-character literals compile instead of looping" do
      assert {:ok, _} = Compiler.parse("'abc' 0.0 'def'")
      assert {:error, _} = Compiler.parse("'abc")
    end

    test "more than four currency signs returns an error not an exception" do
      assert {:error, message} = Compiler.parse("¤¤¤¤¤0.00")
      assert is_binary(message)
      assert message =~ "currency"
    end

    test "scientific Decimal and zero format without raising" do
      assert {:ok, sci} =
               Cldr.Number.to_string(Decimal.new("1234"), Ysc.Cldr,
                 locale: :en,
                 format: :scientific
               )

      assert is_binary(sci)
      assert sci != ""

      assert {:ok, zero} =
               Cldr.Number.to_string(Decimal.new(0), Ysc.Cldr,
                 locale: :en,
                 format: :scientific
               )

      assert is_binary(zero)
    end

    test "round_significant does not raise on Decimal zero digits" do
      zero = Decimal.new(0)
      assert Cldr.Math.round_significant(zero, 0) == zero

      assert Cldr.Math.round_significant(Decimal.new("1.23"), 0) ==
               Decimal.new("1.23")
    end
  end

  describe "app still uses Cldr.Number only as a provider" do
    test "Ysc.Cldr keeps Number among providers and :en only" do
      cldr = File.read!(@cldr)
      assert cldr =~ "Cldr.Number,"
      assert cldr =~ "locales: [:en]"
      assert cldr =~ "default_locale: :en"
      refute cldr =~ "Cldr.Number.to_string"
    end

    test "config still points Money and Cldr at Ysc.Cldr" do
      config = File.read!(@config_exs)
      assert config =~ "config :ex_cldr, default_backend: Ysc.Cldr"
      assert config =~ "config :ex_money, default_cldr_backend: Ysc.Cldr"
    end

    test "MoneyHelper still rewrites leftover $- if a format emits it" do
      helper = File.read!(@money_helper)

      assert helper =~
               ~s|normalize_negative_currency_display({:ok, "$-" <> rest})|

      assert helper =~ ~s|{:ok, "-$" <> rest}|
    end
  end
end
