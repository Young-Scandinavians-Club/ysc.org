defmodule Ysc.JokenUpgradeTest do
  @moduledoc """
  Guards the joken 2.7.0 → 2.8.0 upgrade.

  2.8.0 is a patch-style minor: default `exp`/`nbf` claims reject a
  non-numeric value (RFC 7519 NumericDate; Erlang term order used to
  treat a string/null `exp` as never-expire), and a before hook that
  halts with a non-`{:error, reason}` tuple now returns
  `{:error, :wrong_hook_return}` instead of succeeding. Peek still
  returns `{:error, :token_malformed}` for invalid tokens (2.7.0).
  Elixir floor stays `~> 1.16` (we are 1.20 / OTP 27). jose stays on
  the 1.11.13 override (`~> 1.11.12`).

  We sign Google Wallet JWTs with `Signer.create("RS256", %{"pem" =>
  ...})` and `generate_and_sign/3` on an empty token config. We do not
  use `Joken.Config.default_claims/1`, peek, hooks, or JWK signers.
  """
  use ExUnit.Case, async: true

  @joken Path.expand("../../deps/joken/lib/joken.ex", __DIR__)
  @signer Path.expand("../../deps/joken/lib/joken/signer.ex", __DIR__)
  @config Path.expand("../../deps/joken/lib/joken/config.ex", __DIR__)
  @hooks Path.expand("../../deps/joken/lib/joken/hooks.ex", __DIR__)
  @changelog Path.expand("../../deps/joken/CHANGELOG.md", __DIR__)
  @package_mix Path.expand("../../deps/joken/mix.exs", __DIR__)
  @google_wallet Path.expand("../../lib/ysc/google_wallet.ex", __DIR__)
  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)

  setup_all do
    {:module, Joken} = Code.ensure_loaded(Joken)
    {:module, Joken.Signer} = Code.ensure_loaded(Joken.Signer)
    {:module, Joken.Config} = Code.ensure_loaded(Joken.Config)
    {:module, Joken.Hooks} = Code.ensure_loaded(Joken.Hooks)
    pem = generate_test_rsa_pem()
    {:ok, pem: pem, signer: Joken.Signer.create("RS256", %{"pem" => pem})}
  end

  describe "2.8.0 Hex lock and public APIs" do
    test "locks the Hex package to 2.8.0" do
      assert to_string(Application.spec(:joken, :vsn)) == "2.8.0"
    end

    test "mix.exs pins the 2.8.0 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:joken, "~> 2.8.0"}|
    end

    test "companion lock is 2.8.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"joken": {:hex, :joken, "2.8.0"|
      refute lock =~ ~s|"joken": {:hex, :joken, "2.7.0"|
    end

    test "jose stays on the 1.11.13 override" do
      assert to_string(Application.spec(:jose, :vsn)) == "1.11.13"
      mix_exs = File.read!(@package_mix)
      assert mix_exs =~ ~s|{:jose, "~> 1.11.12"}|
    end

    test "Signer.create and generate_and_sign still exist" do
      assert {:module, Joken} = Code.ensure_loaded(Joken)
      assert {:module, Joken.Signer} = Code.ensure_loaded(Joken.Signer)

      assert function_exported?(Joken.Signer, :create, 2)
      assert function_exported?(Joken.Signer, :create, 3)
      assert function_exported?(Joken, :generate_and_sign, 1)
      assert function_exported?(Joken, :generate_and_sign, 3)
      assert function_exported?(Joken, :peek_header, 1)
      assert function_exported?(Joken, :peek_claims, 1)
      assert function_exported?(Joken.Config, :default_claims, 0)
      assert function_exported?(Joken.Config, :default_claims, 1)
    end

    test "package elixir requirement is still 1.16 which we satisfy" do
      mix_exs = File.read!(@package_mix)
      assert mix_exs =~ ~s(elixir: "~> 1.16")
      assert Version.match?(System.version(), "~> 1.16")
    end
  end

  describe "Google Wallet PEM signer call site" do
    test "create/2 still accepts an RS256 PEM map", %{signer: signer} do
      assert %Joken.Signer{alg: "RS256"} = signer
    end

    test "generate_and_sign/3 still signs extra claims with an empty token config",
         %{signer: signer} do
      claims = %{
        "iss" => "wallet-test@test-project.iam.gserviceaccount.com",
        "aud" => "google",
        "typ" => "savetowallet",
        "iat" => System.os_time(:second),
        "payload" => %{"eventTicketClasses" => []}
      }

      assert {:ok, jwt, signed} = Joken.generate_and_sign(%{}, claims, signer)
      assert is_binary(jwt)
      assert length(String.split(jwt, ".")) == 3
      assert signed["typ"] == "savetowallet"
      assert signed["aud"] == "google"
      assert signed["iss"] == claims["iss"]
      assert signed["payload"] == claims["payload"]
      refute Map.has_key?(signed, "exp")
      refute Map.has_key?(signed, "nbf")
    end

    test "google_wallet still uses the PEM map signer and generate_and_sign/3" do
      source = File.read!(@google_wallet)

      assert source =~
               ~s[signer = Joken.Signer.create("RS256", %{"pem" => creds.private_key})]

      assert source =~ "Joken.generate_and_sign(%{}, claims, signer)"
      refute source =~ "Joken.peek_"
      refute source =~ "JOSE.JWK"
      refute source =~ "Joken.Config"
      refute source =~ "Joken.Hooks"
      refute source =~ "default_claims"
    end
  end

  describe "2.8.0 default exp/nbf reject non-numeric values" do
    test "changelog documents the NumericDate and hook-halt fixes" do
      changelog = File.read!(@changelog)

      assert changelog =~
               "default `exp` and `nbf` claims reject a non-numeric value"

      assert changelog =~
               "non-`{:error, reason}` tuples now return `{:error, :wrong_hook_return}`"
    end

    test "numeric exp still validates against current_time" do
      exp_claim = Joken.Config.default_claims()["exp"]
      now = Joken.current_time()
      assert exp_claim.validate.(now + 60, %{}, %{})
      refute exp_claim.validate.(now - 1, %{}, %{})
      assert exp_claim.validate.(now + 1.5, %{}, %{})
    end

    test "non-numeric exp is rejected instead of never-expiring" do
      exp_claim = Joken.Config.default_claims()["exp"]
      refute exp_claim.validate.("never", %{}, %{})
      refute exp_claim.validate.(nil, %{}, %{})
      refute exp_claim.validate.(:null, %{}, %{})
      refute exp_claim.validate.(%{}, %{}, %{})
      refute exp_claim.validate.([1], %{}, %{})
      refute exp_claim.validate.(true, %{}, %{})
    end

    test "numeric nbf still validates against current_time" do
      nbf_claim = Joken.Config.default_claims()["nbf"]
      now = Joken.current_time()
      assert nbf_claim.validate.(now, %{}, %{})
      assert nbf_claim.validate.(now - 1, %{}, %{})
      refute nbf_claim.validate.(now + 60, %{}, %{})
    end

    test "non-numeric nbf is rejected" do
      nbf_claim = Joken.Config.default_claims()["nbf"]
      refute nbf_claim.validate.("now", %{}, %{})
      refute nbf_claim.validate.(nil, %{}, %{})
      refute nbf_claim.validate.(:null, %{}, %{})
    end

    test "empty token config we use still skips default exp/nbf generation", %{
      signer: signer
    } do
      assert {:ok, _jwt, signed} =
               Joken.generate_and_sign(%{}, %{"typ" => "savetowallet"}, signer)

      refute Map.has_key?(signed, "exp")
      refute Map.has_key?(signed, "nbf")
    end

    test "config source guards NumericDate with is_number" do
      source = File.read!(@config)
      assert source =~ "defp valid_exp?(exp) when is_number(exp)"
      assert source =~ "defp valid_exp?(_exp), do: false"
      assert source =~ "defp valid_nbf?(nbf) when is_number(nbf)"
      assert source =~ "defp valid_nbf?(_nbf), do: false"
      assert source =~ "RFC 7519 requires exp and nbf to be a NumericDate"
    end
  end

  describe "2.8.0 before-hook halt is never a success (unused)" do
    test "hooks source treats non-error before-halt as :wrong_hook_return" do
      source = File.read!(@hooks)

      assert source =~
               "{:halt, {:error, _reason} = err} -> {:halt, err}"

      assert source =~ "_ -> {:halt, {:error, :wrong_hook_return}}"

      assert source =~
               "A before hook must always halt with an `{:error, reason}` tuple"
    end
  end

  describe "2.7.0 peek flags invalid tokens" do
    test "peek_claims/1 still returns claims for a valid token", %{
      signer: signer
    } do
      assert {:ok, jwt, _} =
               Joken.generate_and_sign(%{}, %{"typ" => "savetowallet"}, signer)

      assert {:ok, peeked} = Joken.peek_claims(jwt)
      assert peeked["typ"] == "savetowallet"
    end

    test "peek_header/1 still returns the JOSE header for a valid token", %{
      signer: signer
    } do
      assert {:ok, jwt, _} = Joken.generate_and_sign(%{}, %{}, signer)
      assert {:ok, header} = Joken.peek_header(jwt)
      assert header["alg"] == "RS256"
    end

    test "peek_claims/1 returns :token_malformed for non-JSON payload" do
      header = Base.url_encode64(~s({"alg":"RS256"}), padding: false)
      payload = Base.url_encode64("not-json", padding: false)
      token = "#{header}.#{payload}.sig"

      assert Joken.peek_claims(token) == {:error, :token_malformed}
    end

    test "peek_header/1 returns :token_malformed for non-JSON header" do
      header = Base.url_encode64("not-json", padding: false)
      payload = Base.url_encode64(~s({"typ":"JWT"}), padding: false)
      token = "#{header}.#{payload}.sig"

      assert Joken.peek_header(token) == {:error, :token_malformed}
    end

    test "peek_claims/1 returns :token_malformed for a token that is not three parts" do
      assert Joken.peek_claims("not-a-jwt") == {:error, :token_malformed}
    end
  end

  describe "2.7.0 Signer.create JOSE.JWK (unused)" do
    test "create/2 accepts a JOSE.JWK for RS256", %{pem: pem} do
      jwk = JOSE.JWK.from_pem(pem)
      signer = Joken.Signer.create("RS256", jwk)

      assert %Joken.Signer{alg: "RS256"} = signer

      assert {:ok, jwt, claims} =
               Joken.generate_and_sign(%{}, %{"sub" => "jwk-probe"}, signer)

      assert is_binary(jwt)
      assert claims["sub"] == "jwk-probe"
    end

    test "signer source still has the PEM map clause we use and the JWK clause" do
      source = File.read!(@signer)
      assert source =~ ~s[def create(alg, %{"pem" => pem}, headers)]
      assert source =~ "def create(alg, %JWK{} = key, headers)"
    end

    test "peek source rescues decode failures as :token_malformed" do
      source = File.read!(@joken)
      assert source =~ "rescue"
      assert source =~ "{:error, :token_malformed}"
    end
  end

  defp generate_test_rsa_pem do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    :public_key.pem_encode([pem_entry])
  end
end
