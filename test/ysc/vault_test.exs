defmodule Ysc.VaultTest do
  @moduledoc """
  Tests for Vault module.

  These tests verify:
  - Vault initialization
  - Encryption key handling
  - Fallback to default key in development
  """
  use ExUnit.Case, async: false

  alias Ysc.Vault

  describe "init/1" do
    test "initializes vault with default config" do
      # This test verifies that the vault can be initialized
      # The actual encryption/decryption would require Cloak to be properly configured
      config = [
        otp_app: :ysc,
        ciphers: []
      ]

      result = Vault.init(config)

      assert {:ok, vault_config} = result
      assert Keyword.has_key?(vault_config, :ciphers)
      assert Keyword.has_key?(vault_config[:ciphers], :default)
    end

    test "uses default key when CLOAK_ENCRYPTION_KEY is not set" do
      # Temporarily unset the env var if it exists
      original_key = System.get_env("CLOAK_ENCRYPTION_KEY")
      System.delete_env("CLOAK_ENCRYPTION_KEY")

      try do
        config = [
          otp_app: :ysc,
          ciphers: []
        ]

        result = Vault.init(config)

        assert {:ok, vault_config} = result
        # Should use the default development key
        {_cipher, cipher_config} = vault_config[:ciphers][:default]
        assert Keyword.has_key?(cipher_config, :key)
        key = Keyword.get(cipher_config, :key)
        assert byte_size(key) == 32
      after
        # Restore original env var if it existed
        if original_key do
          System.put_env("CLOAK_ENCRYPTION_KEY", original_key)
        end
      end
    end

    test "validates key size when CLOAK_ENCRYPTION_KEY is set" do
      # Test with invalid key size
      # Less than 32 bytes
      invalid_key = Base.encode64("short-key")

      try do
        System.put_env("CLOAK_ENCRYPTION_KEY", invalid_key)

        config = [
          otp_app: :ysc,
          ciphers: []
        ]

        assert_raise RuntimeError, ~r/Invalid CLOAK_ENCRYPTION_KEY/, fn ->
          Vault.init(config)
        end
      after
        System.delete_env("CLOAK_ENCRYPTION_KEY")
      end
    end

    test "accepts valid 32-byte key" do
      # Generate a valid 32-byte key
      valid_key = :crypto.strong_rand_bytes(32) |> Base.encode64()

      try do
        System.put_env("CLOAK_ENCRYPTION_KEY", valid_key)

        config = [
          otp_app: :ysc,
          ciphers: []
        ]

        result = Vault.init(config)

        assert {:ok, vault_config} = result
        {_cipher, cipher_config} = vault_config[:ciphers][:default]
        key = Keyword.get(cipher_config, :key)
        assert byte_size(key) == 32
      after
        System.delete_env("CLOAK_ENCRYPTION_KEY")
      end
    end
  end
end
