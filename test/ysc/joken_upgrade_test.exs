defmodule Ysc.JokenUpgradeTest do
  @moduledoc """
  Guards the joken 2.6.2 → 2.7.0 upgrade.

  2.7.0 is a minor: Elixir 1.16 / OTP 26 floor (we are 1.20 / OTP 27),
  `Joken.Signer.create/2` accepts a `%JOSE.JWK{}`, and `peek_header/1` /
  `peek_claims/1` rescue decode failures as `{:error, :token_malformed}`.
  We sign Google Wallet JWTs with `Signer.create("RS256", %{"pem" => ...})`
  and `generate_and_sign/3`. We do not use peek or JWK signers.
  """
  use ExUnit.Case, async: true

  @joken Path.expand("../../deps/joken/lib/joken.ex", __DIR__)
  @signer Path.expand("../../deps/joken/lib/joken/signer.ex", __DIR__)
  @google_wallet Path.expand("../../lib/ysc/google_wallet.ex", __DIR__)

  setup_all do
    {:module, Joken} = Code.ensure_loaded(Joken)
    {:module, Joken.Signer} = Code.ensure_loaded(Joken.Signer)
    pem = generate_test_rsa_pem()
    {:ok, pem: pem, signer: Joken.Signer.create("RS256", %{"pem" => pem})}
  end

  describe "2.7.0 Hex lock and public APIs" do
    test "locks the Hex package to 2.7.0" do
      assert to_string(Application.spec(:joken, :vsn)) == "2.7.0"
    end

    test "jose stays on the 1.11.12 override" do
      assert to_string(Application.spec(:jose, :vsn)) == "1.11.12"
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
    end

    test "package elixir requirement is 1.16 which we satisfy" do
      mix_exs = File.read!(Path.expand("../../deps/joken/mix.exs", __DIR__))
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
    end

    test "google_wallet still uses the PEM map signer and generate_and_sign/3" do
      source = File.read!(@google_wallet)

      assert source =~
               ~s[signer = Joken.Signer.create("RS256", %{"pem" => creds.private_key})]

      assert source =~ "Joken.generate_and_sign(%{}, claims, signer)"
      refute source =~ "Joken.peek_"
      refute source =~ "JOSE.JWK"
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

    test "signer source still has the PEM map clause we use and the new JWK clause" do
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
