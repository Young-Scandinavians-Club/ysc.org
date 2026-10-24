defmodule QueryConsole.PlugCryptoUpgradeTest do
  @moduledoc """
  Guards the plug_crypto 2.2.0 → 2.2.1 upgrade.

  2.2.1 is a patch with no documented breaking changes. It patches
  EEF-CVE-2026-105963 (MEDIUM / GHSA-ffw9-w85g-f2vh): wrong-typed
  arguments to `Plug.Crypto` raise `ArgumentError` instead of a
  `FunctionClauseError` whose stacktrace included the secret key base.

  Query Console reaches plug_crypto through Phoenix/Plug session
  cookies. Public sign/verify APIs are unchanged. Phoenix still lists
  `plug_crypto ~> 2.2`, so mix.exs keeps an override pin.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @crypto_src Path.expand("../../deps/plug_crypto/lib/plug/crypto.ex", __DIR__)
  @changelog Path.expand("../../deps/plug_crypto/CHANGELOG.md", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:plug_crypto)
    {:module, Plug.Crypto} = Code.ensure_loaded(Plug.Crypto)
    :ok
  end

  describe "2.2.1 Hex lock and public APIs" do
    test "locks the Hex package to 2.2.1" do
      assert to_string(Application.spec(:plug_crypto, :vsn)) == "2.2.1"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:plug_crypto, "~> 2.2.1", override: true})
    end

    test "companion lock is 2.2.1" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"plug_crypto": {:hex, :plug_crypto, "2.2.1"|
      refute lock =~ ~s|"plug_crypto": {:hex, :plug_crypto, "2.2.0"|
    end

    test "sign/verify and secure_compare still exist" do
      assert function_exported?(Plug.Crypto, :sign, 3)
      assert function_exported?(Plug.Crypto, :verify, 3)
      assert function_exported?(Plug.Crypto, :secure_compare, 2)
    end
  end

  describe "2.2.1 changelog" do
    test "documents CVE-2026-105963" do
      changelog = File.read!(@changelog)
      assert changelog =~ "CVE-2026-105963"
      assert changelog =~ "GHSA-ffw9-w85g-f2vh"
    end
  end

  describe "EEF-CVE-2026-105963 wrong-typed args" do
    test "sign raises ArgumentError without the secret in the stacktrace" do
      secret = "SECRET-" <> String.duplicate("x", 20)

      try do
        Plug.Crypto.sign(secret, nil, 1)
        flunk("expected an exception")
      rescue
        e in [ArgumentError] ->
          refute Exception.format(:error, e, __STACKTRACE__) =~ secret
      end
    end

    test "catch-all clauses exist so FunctionClauseError cannot leak args" do
      source = File.read!(@crypto_src)
      assert source =~ "raise ArgumentError, bad_args(key_base, salt, opts)"
      assert source =~ ~s|def secure_compare(_left, _right) do|
    end
  end
end
