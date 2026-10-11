defmodule Ysc.DecimalUpgradeTest do
  @moduledoc """
  Guards the decimal 3.1.1 → 3.2.0 upgrade.

  3.1.2 is a security patch for CVE-2026-97853 (GHSA-6c27-994x-c52f):
  `Decimal.round/3` no longer builds a result at the full requested
  scale before applying context precision, so a caller-controlled
  `places` cannot exhaust memory. `to_integer/1` and `to_float/1`
  return 0 for a zero coefficient without computing `pow10(exp)`.

  3.2.0 includes that fix plus faster arithmetic and Decimal Arithmetic
  spec alignment. `round/3` now raises `Decimal.Error` when `-places`
  is outside the context exponent range or the result would need more
  digits than the precision (for example `Decimal.round("1.5", 7000)`).
  `compare/2` raises `Decimal.Error` for NaN. We round money with
  places 0/1/2 (`:half_up`) and compare finite amounts. We do not pass
  NaN, custom `Decimal.Context`, or user-controlled places.
  """
  use ExUnit.Case, async: true

  alias Ysc.MoneyHelper

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/decimal/CHANGELOG.md", __DIR__)
  @decimal_src Path.expand("../../deps/decimal/lib/decimal.ex", __DIR__)
  @money_helpers Path.expand("../../lib/ysc/money_helpers.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:decimal)
    {:module, Decimal} = Code.ensure_loaded(Decimal)
    {:module, Decimal.Error} = Code.ensure_loaded(Decimal.Error)
    {:module, Decimal.Context} = Code.ensure_loaded(Decimal.Context)
    :ok
  end

  describe "3.2.0 Hex lock and public APIs" do
    test "locks the Hex package to 3.2.0" do
      assert to_string(Application.spec(:decimal, :vsn)) == "3.2.0"
    end

    test "mix.exs pins the 3.2.0 floor override" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:decimal, "~> 3.2.0", override: true})
    end

    test "companion lock is 3.2.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"decimal": {:hex, :decimal, "3.2.0"|
      refute lock =~ ~s|"decimal": {:hex, :decimal, "3.1.1"|
    end

    test "arithmetic, compare, and conversion APIs we use still load" do
      {:module, Decimal} = Code.ensure_loaded(Decimal)
      assert function_exported?(Decimal, :new, 1)
      assert function_exported?(Decimal, :parse, 1)
      assert function_exported?(Decimal, :add, 2)
      assert function_exported?(Decimal, :sub, 2)
      assert function_exported?(Decimal, :mult, 2)
      assert function_exported?(Decimal, :div, 2)
      assert function_exported?(Decimal, :round, 1)
      assert function_exported?(Decimal, :round, 2)
      assert function_exported?(Decimal, :round, 3)
      assert function_exported?(Decimal, :compare, 2)
      assert function_exported?(Decimal, :eq?, 2)
      assert function_exported?(Decimal, :gt?, 2)
      assert function_exported?(Decimal, :gte?, 2)
      assert function_exported?(Decimal, :abs, 1)
      assert function_exported?(Decimal, :negate, 1)
      assert function_exported?(Decimal, :to_string, 1)
      assert function_exported?(Decimal, :to_string, 2)
      assert function_exported?(Decimal, :to_integer, 1)
      assert function_exported?(Decimal, :to_float, 1)
    end

    test "money helpers still round with small places" do
      source = File.read!(@money_helpers)
      assert source =~ "|> Decimal.round(2)"
      assert source =~ "|> Decimal.round(0, :half_up)"
      refute source =~ "Decimal.Context"
    end
  end

  describe "3.2.0 and 3.1.2 changelog" do
    test "3.2.0 documents faster arithmetic and round/3 Decimal.Error" do
      changelog = File.read!(@changelog)

      v320 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "v3.2.0"))

      assert v320
      assert v320 =~ "Make most operations faster"
      assert v320 =~ "Decimal.Error"
      assert v320 =~ "Decimal.round/3"
      refute v320 =~ "Breaking"
    end

    test "3.1.2 documents CVE-2026-97853 round/3 allocation fix" do
      changelog = File.read!(@changelog)

      v312 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "v3.1.2"))

      assert v312
      assert v312 =~ "CVE-2026-97853"
      assert v312 =~ "GHSA-6c27-994x-c52f"
      assert v312 =~ "Decimal.round/3"
      refute v312 =~ "Breaking"
    end
  end

  describe "money rounding we use still holds" do
    test "round/2 to two places uses half_up" do
      assert Decimal.eq?(
               Decimal.round(Decimal.new("10.994"), 2),
               Decimal.new("10.99")
             )

      assert Decimal.eq?(
               Decimal.round(Decimal.new("10.995"), 2),
               Decimal.new("11.00")
             )
    end

    test "round/3 to zero places with half_up matches money_to_cents" do
      cents =
        Decimal.new("10.995")
        |> Decimal.mult(100)
        |> Decimal.round(0, :half_up)
        |> Decimal.to_integer()

      assert cents == 1100
      assert MoneyHelper.money_to_cents(Money.new(:USD, "10.995")) == 1100
    end

    test "cents_to_dollars still divides by 100 and rounds to two places" do
      assert Decimal.eq?(
               MoneyHelper.cents_to_dollars(1099),
               Decimal.new("10.99")
             )

      assert Decimal.eq?(MoneyHelper.cents_to_dollars(1), Decimal.new("0.01"))
    end

    test "percent and compare helpers still return atoms for finite amounts" do
      assert Decimal.compare(Decimal.new("100"), Decimal.new(0)) == :gt
      assert Decimal.compare(Decimal.new(0), Decimal.new(0)) == :eq
      assert Decimal.gt?(Decimal.new("25.5"), 0)
      assert Decimal.eq?(Decimal.new("50"), Decimal.new("50.0"))
    end

    test "div of money-scale values stays exact after round 2" do
      ratio =
        Decimal.new(150)
        |> Decimal.div(Decimal.new(100))
        |> Decimal.round(2)

      assert Decimal.eq?(ratio, Decimal.new("1.50"))
    end
  end

  describe "CVE-2026-97853 round/3 places bound" do
    test "huge negative places raise Decimal.Error without exhausting memory" do
      {elapsed_us, :ok} =
        :timer.tc(fn ->
          assert_raise Decimal.Error, fn ->
            Decimal.round(Decimal.new("1.5"), -50_000_000)
          end

          :ok
        end)

      assert elapsed_us < 1_000_000
    end

    test "huge positive places raise Decimal.Error instead of padding" do
      {elapsed_us, :ok} =
        :timer.tc(fn ->
          assert_raise Decimal.Error, fn ->
            Decimal.round(Decimal.new("1.5"), 7000)
          end

          :ok
        end)

      assert elapsed_us < 1_000_000
    end

    test "to_integer and to_float of a huge-exponent zero return immediately" do
      zero = %Decimal{sign: 1, coef: 0, exp: 1_000_000_000}

      {int_us, 0} = :timer.tc(fn -> Decimal.to_integer(zero) end)
      {float_us, float_zero} = :timer.tc(fn -> Decimal.to_float(zero) end)

      assert float_zero == +0.0
      assert int_us < 100_000
      assert float_us < 100_000
    end

    test "round/3 rejects places outside the exponent range in source" do
      source = File.read!(@decimal_src)
      assert source =~ "places outside the exponent range"
      assert source =~ "def to_integer(%Decimal{coef: 0}), do: 0"
      assert source =~ "def to_float(%Decimal{coef: 0}), do: 0.0"
    end
  end
end
