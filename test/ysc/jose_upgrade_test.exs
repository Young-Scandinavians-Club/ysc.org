defmodule Ysc.JoseUpgradeTest do
  @moduledoc """
  Guards the jose 1.11.12 → 1.11.13 upgrade.

  1.11.13 is a patch released the same day as eight Hex advisories
  (EEF-CVE-2026-65625 through EEF-CVE-2026-65632). Public Joken RS256
  PEM signing used by Google Wallet is unchanged. crypto_fallback now
  defaults to false. joken still lists `~> 1.11.12` and goth `~> 1.11`,
  so mix.exs keeps an override pin.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/jose/CHANGELOG.md", __DIR__)
  @jose_erl Path.expand("../../deps/jose/src/jose.erl", __DIR__)
  @jose_app Path.expand("../../deps/jose/src/jose.app.src", __DIR__)
  @jose_server Path.expand("../../deps/jose/src/jose_server.erl", __DIR__)
  @jwa Path.expand("../../deps/jose/src/jwa/jose_jwa.erl", __DIR__)
  @jwa_aes Path.expand("../../deps/jose/src/jwa/jose_jwa_aes.erl", __DIR__)
  @jwe_zip Path.expand("../../deps/jose/src/jwe/jose_jwe_zip.erl", __DIR__)
  @jwe_rsa Path.expand("../../deps/jose/src/jwe/jose_jwe_alg_rsa.erl", __DIR__)
  @jwk Path.expand("../../deps/jose/src/jwk/jose_jwk.erl", __DIR__)
  @jwk_ec Path.expand("../../deps/jose/src/jwk/jose_jwk_kty_ec.erl", __DIR__)
  @jwk_rsa Path.expand("../../deps/jose/src/jwk/jose_jwk_kty_rsa.erl", __DIR__)
  @public_key_hrl Path.expand(
                    "../../deps/jose/include/jose_public_key.hrl",
                    __DIR__
                  )
  @google_wallet Path.expand("../../lib/ysc/google_wallet.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jose)
    {:module, JOSE} = Code.ensure_loaded(JOSE)
    {:module, JOSE.JWK} = Code.ensure_loaded(JOSE.JWK)
    {:module, JOSE.JWE} = Code.ensure_loaded(JOSE.JWE)
    {:module, JOSE.JWS} = Code.ensure_loaded(JOSE.JWS)
    {:module, Joken} = Code.ensure_loaded(Joken)
    {:module, Joken.Signer} = Code.ensure_loaded(Joken.Signer)
    {:module, :jose} = Code.ensure_loaded(:jose)
    :ok
  end

  describe "1.11.13 Hex lock and public APIs" do
    test "locks the Hex package to 1.11.13" do
      assert to_string(Application.spec(:jose, :vsn)) == "1.11.13"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:jose, "~> 1.11.13", override: true})
    end

    test "companion lock is 1.11.13" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"jose": {:hex, :jose, "1.11.13"|
      refute lock =~ ~s|"jose": {:hex, :jose, "1.11.12"|
    end

    test "Joken and JOSE APIs we use still exist" do
      assert function_exported?(JOSE.JWK, :from_pem, 1)
      assert function_exported?(JOSE.JWK, :from_oct, 1)
      assert function_exported?(JOSE.JWK, :generate_key, 1)
      assert function_exported?(JOSE.JWK, :shared_secret, 2)
      assert function_exported?(JOSE.JWE, :block_encrypt, 3)
      assert function_exported?(JOSE.JWE, :block_decrypt, 2)
      assert function_exported?(JOSE.JWS, :sign, 3)
      assert function_exported?(JOSE.JWS, :verify, 2)
      assert function_exported?(Joken.Signer, :create, 2)
      assert function_exported?(Joken, :generate_and_sign, 3)
      assert function_exported?(:jose, :crypto_fallback, 0)
      assert function_exported?(:jose, :zip_size_maximum, 0)
    end
  end

  describe "1.11.13 changelog" do
    test "documents the eight Hex advisories" do
      changelog = File.read!(@changelog)

      v11113 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "1.11.13"))

      assert v11113
      assert v11113 =~ "GHSA-6gxw-6f7r-cjr6"
      assert v11113 =~ "GHSA-vwvr-f994-6j9j"
      assert v11113 =~ "GHSA-wfpv-qxp8-x5gm"
      assert v11113 =~ "GHSA-fpj2-9h59-32pp"
      assert v11113 =~ "GHSA-h4gx-8jq2-mfhc"
      assert v11113 =~ "GHSA-xvr2-gggj-h2pp"
      assert v11113 =~ "GHSA-3m45-vrpj-xmrq"
      assert v11113 =~ "GHSA-44hw-rpw9-mwg4"
    end
  end

  describe "Google Wallet RS256 PEM signing" do
    test "Joken still signs with an RS256 PEM map" do
      pem = generate_test_rsa_pem()
      signer = Joken.Signer.create("RS256", %{"pem" => pem})
      assert %Joken.Signer{alg: "RS256"} = signer

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
    end

    test "google_wallet still uses the PEM map signer" do
      source = File.read!(@google_wallet)

      assert source =~
               ~s[signer = Joken.Signer.create("RS256", %{"pem" => creds.private_key})]

      assert source =~ "Joken.generate_and_sign(%{}, claims, signer)"
      refute source =~ "JOSE.JWE"
      refute source =~ "JOSE.JWK.shared_secret"
    end
  end

  describe "EEF-CVE-2026-65630 crypto_fallback default" do
    test "crypto_fallback is false unless explicitly enabled" do
      assert JOSE.crypto_fallback() == false
      assert :jose.crypto_fallback() == false

      app_src = File.read!(@jose_app)
      assert app_src =~ "{crypto_fallback, false}"

      server = File.read!(@jose_server)
      assert server =~ "application:get_env(jose, crypto_fallback, false)"
    end
  end

  describe "EEF-CVE-2026-65627 JWE zip bound" do
    test "zip_size_maximum defaults to 1 MiB" do
      assert :jose.zip_size_maximum() == 1_048_576

      app_src = File.read!(@jose_app)
      assert app_src =~ "{zip_size_maximum, 1048576}"

      zip = File.read!(@jwe_zip)
      assert zip =~ "ZipSizeMaximum = jose:zip_size_maximum()"
      assert zip =~ "safe_inflate("
      assert zip =~ "maximum uncompressed size is set to ~w bytes"
    end
  end

  describe "EEF-CVE-2026-65625 AEAD tag length" do
    test "A256GCM still round-trips with a 128-bit tag" do
      jwk = JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32))

      compact =
        jwk
        |> JOSE.JWE.block_encrypt("hello", %{"alg" => "dir", "enc" => "A256GCM"})
        |> JOSE.JWE.compact()
        |> elem(1)

      assert length(String.split(compact, ".")) == 5

      {plaintext, _jwe} = JOSE.JWE.block_decrypt(jwk, compact)
      assert plaintext == "hello"
    end

    test "a truncated GCM tag is rejected instead of authenticated" do
      jwk = JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32))

      compact =
        jwk
        |> JOSE.JWE.block_encrypt("hello", %{"alg" => "dir", "enc" => "A256GCM"})
        |> JOSE.JWE.compact()
        |> elem(1)

      [protected, enc_key, iv, ciphertext, tag] = String.split(compact, ".")
      assert byte_size(Base.url_decode64!(tag, padding: false)) == 16

      truncated = Base.url_encode64(<<0>>, padding: false)
      forged = Enum.join([protected, enc_key, iv, ciphertext, truncated], ".")

      assert {:error, _} = JOSE.JWE.block_decrypt(jwk, forged)
    end

    test "dispatcher and AES-GCM fallback reject non-128-bit tags" do
      jwa = File.read!(@jwa)
      assert jwa =~ "andalso bit_size(CipherTag) =/= 128 ->"
      assert jwa =~ "error;"

      aes = File.read!(@jwa_aes)
      assert aes =~ "andalso bit_size(CipherTag) =:= 128 ->"
    end
  end

  describe "EEF-CVE-2026-65628 mismatched shared_secret" do
    test "raises instead of looping when peer kty does not match" do
      server = JOSE.JWK.generate_key({:ec, "P-256"})
      peer = JOSE.JWK.generate_key({:rsa, 2048}) |> JOSE.JWK.to_public()

      error =
        assert_raise ArgumentError, fn ->
          JOSE.JWK.shared_secret(peer, server)
        end

      assert error.message =~ "jose_jwk_kty_rsa"
      assert error.message =~ "jose_jwk_kty_ec"
    end

    test "shared_secret source fails closed on decoded mismatched kty" do
      source = File.read!(@jwk)

      assert source =~
               "erlang:error({badarg, [kty_module(YourKTY), kty_module(MyKTY)]})"
    end
  end

  describe "EEF-CVE-2026-65632 ECDSA signature length" do
    test "ES256 verifies a canonical signature and rejects a truncated one" do
      jwk = JOSE.JWK.generate_key({:ec, "P-256"})

      compact =
        jwk
        |> JOSE.JWS.sign("hello", %{"alg" => "ES256"})
        |> JOSE.JWS.compact()
        |> elem(1)

      [header, payload, signature] = String.split(compact, ".")
      assert byte_size(Base.url_decode64!(signature, padding: false)) == 64

      {true, _payload, _jws} = JOSE.JWS.verify(jwk, compact)

      short = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      {false, _, _} =
        JOSE.JWS.verify(jwk, Enum.join([header, payload, short], "."))
    end

    test "EC verify splits on the curve's canonical R||S size" do
      source = File.read!(@jwk_ec)
      assert source =~ "RSSize = jws_alg_to_r_s_size(JWSALG)"
      assert source =~ "<< RBin:RSSize/binary, SBin:RSSize/binary >>"
    end
  end

  describe "remaining 1.11.13 source patches" do
    test "RSA JWE unwrap substitutes a random CEK on failure" do
      source = File.read!(@jwe_rsa)
      assert source =~ "RandomKey = ENCModule:next_cek(ENC)"
      assert source =~ "Prefer RSA-OAEP or RSA-OAEP-256"
    end

    test "PKCS#8 export uses PBKDF2-HMAC-SHA256 with 600_000 iterations" do
      source = File.read!(@public_key_hrl)
      assert source =~ "-define(JOSE_PBES2_ITERATION_COUNT, 600000)."
      assert source =~ "-define(JOSE_PBES2_SALT_BYTES, 16)."
    end

    test "RSA private-key prime recovery is bounded" do
      source = File.read!(@jwk_rsa)
      assert source =~ "erlang:error({badarg, [Key0]})"
    end

    test "zip_size_maximum/0 is exported from jose.erl" do
      source = File.read!(@jose_erl)
      assert source =~ "-export([zip_size_maximum/0])."
      assert source =~ "-export([zip_size_maximum/1])."
    end
  end

  defp generate_test_rsa_pem do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    :public_key.pem_encode([pem_entry])
  end
end
