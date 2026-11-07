defmodule Ysc.BrotliUpgradeTest do
  @moduledoc """
  Guards the brotli 0.3.3 → 0.3.4 upgrade.

  0.3.4 patches EEF-CVE-2026-111497 (out-of-bounds write in the bundled
  Brotli decoder). PhoenixBakery uses this at compile time to compress
  static assets. Req may decode `Content-Encoding: br` when the optional
  NIF is present. We pin the patched floor and keep `runtime: false`.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)

  describe "0.3.4 Hex lock" do
    test "mix.exs pins the 0.3.4 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:brotli, "~> 0.3.4", runtime: false})
      refute mix_exs =~ ~s({:brotli, ">= 0.0.0", runtime: false})
    end

    test "companion lock is 0.3.4" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"brotli": {:hex, :brotli, "0.3.4"|
      refute lock =~ ~s|"brotli": {:hex, :brotli, "0.3.3"|
    end

    test "does not ignore the patched advisory" do
      mix_exs = File.read!(@mix_exs)

      ignore =
        mix_exs
        |> String.split("ignore_advisories: [", parts: 2)
        |> Enum.at(1)
        |> String.split("]", parts: 2)
        |> hd()

      refute ignore =~ "EEF-CVE-2026-111497"
    end
  end
end
