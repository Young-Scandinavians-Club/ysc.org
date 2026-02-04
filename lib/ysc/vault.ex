defmodule Ysc.Vault do
  @moduledoc """
  Encryption vault for the YSC application using Cloak.

  Configures AES-256-GCM encryption for sensitive data. The encryption key
  is read from the CLOAK_ENCRYPTION_KEY environment variable, with a fallback
  development key for local development.
  """
  use Cloak.Vault, otp_app: :ysc

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1", key: decode_env!("CLOAK_ENCRYPTION_KEY")
        }
      )

    {:ok, config}
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> case do
      nil ->
        # Fallback to default key for development (32 bytes = 256 bits for AES-256-GCM)
        # This is a development-only key. In production, always set CLOAK_ENCRYPTION_KEY.
        # Generate a proper key with: :crypto.strong_rand_bytes(32) |> Base.encode64()
        "bM0gnyyHEn6fJkQQvqrJRRSC9Cfp/bLrmZ9S3dUKL1k="
        |> Base.decode64!()

      key ->
        decoded = Base.decode64!(key)

        # Validate key size for AES-256-GCM (must be 32 bytes)
        if byte_size(decoded) != 32 do
          raise """
          Invalid CLOAK_ENCRYPTION_KEY: key must be 32 bytes (256 bits) for AES-256-GCM.
          Generate a valid key with: :crypto.strong_rand_bytes(32) |> Base.encode64()
          Current key size: #{byte_size(decoded)} bytes
          """
        end

        decoded
    end
  end
end
