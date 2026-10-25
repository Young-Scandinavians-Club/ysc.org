defmodule QueryConsole.DecimalUpgradeTest do
  @moduledoc """
  Guards the decimal 3.1.1 → 3.2.0 upgrade.

  3.1.2 is a security patch for CVE-2026-97853 (GHSA-6c27-994x-c52f):
  `Decimal.round/3` no longer builds a result at the full requested
  scale before applying context precision, so a caller-controlled
  `places` cannot exhaust memory. `to_integer/1` and `to_float/1`
  return 0 for a zero coefficient without computing `pow10(exp)`.

  3.2.0 includes that fix plus faster arithmetic and Decimal Arithmetic
  spec alignment. `to_string/1` is unchanged. Query Console only
  serializes Postgrex numeric cells with `Decimal.to_string/1`. We do
  not call `round/3`, compare NaN, or pass a custom `Decimal.Context`.
  """
  use ExUnit.Case, async: true

  alias QueryConsole.Runner.Cells

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/decimal/CHANGELOG.md", __DIR__)
  @decimal_src Path.expand("../../deps/decimal/lib/decimal.ex", __DIR__)
  @cells_src Path.expand("../../lib/query_console/runner/cells.ex", __DIR__)

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

    test "companion lock is 3.2.0 and req stays put" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"decimal": {:hex, :decimal, "3.2.0"|
      refute lock =~ ~s|"decimal": {:hex, :decimal, "3.1.1"|
      assert lock =~ ~s|"req": {:hex, :req, "0.7.5"|
      assert lock =~ ~s|"finch": {:hex, :finch, "0.24.0"|
    end

    test "to_string and conversion APIs we use still load" do
      {:module, Decimal} = Code.ensure_loaded(Decimal)
      assert function_exported?(Decimal, :new, 1)
      assert function_exported?(Decimal, :to_string, 1)
      assert function_exported?(Decimal, :to_string, 2)
      assert function_exported?(Decimal, :to_integer, 1)
      assert function_exported?(Decimal, :to_float, 1)
      assert function_exported?(Decimal, :round, 3)
    end

    test "cells still serialize numeric values with Decimal.to_string/1" do
      source = File.read!(@cells_src)
      assert source =~ "def serialize(%Decimal{} = d), do: Decimal.to_string(d)"
      refute source =~ "Decimal.round"
      refute source =~ "Decimal.Context"
      refute source =~ "Decimal.compare"
    end
  end

  describe "3.2.0 and 3.1.2 changelog" do
    test "3.2.0 documents faster arithmetic and unchanged to_string/1" do
      changelog = File.read!(@changelog)

      v320 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "v3.2.0"))

      assert v320
      assert v320 =~ "Make most operations faster"
      assert v320 =~ ~S|`to_string/1` is unchanged|
      assert v320 =~ "Decimal.Error"
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

  describe "Query Console Decimal.to_string usage still holds" do
    test "serializes Postgrex-style numeric cells as Jason-safe strings" do
      amount = Decimal.new("10.50")
      serialized = Cells.serialize(amount)

      assert serialized == Decimal.to_string(amount)
      assert is_binary(serialized)
      assert {:ok, json} = Jason.encode(%{"amount" => serialized})
      assert json =~ "10.50" or json =~ "1.050E+1"
    end

    test "serializes nested lists and maps of decimals" do
      nested = [Decimal.new("1.00"), %{"price" => Decimal.new("2.5")}]
      serialized = Cells.serialize(nested)

      assert hd(serialized) == Decimal.to_string(Decimal.new("1.00"))

      assert serialized |> Enum.at(1) |> Map.fetch!("price") ==
               Decimal.to_string(Decimal.new("2.5"))

      assert {:ok, _} = Jason.encode(serialized)
    end

    test "scientific to_string still matches the default arity" do
      value = Decimal.new("123.45")
      assert Decimal.to_string(value) == Decimal.to_string(value, :scientific)
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
