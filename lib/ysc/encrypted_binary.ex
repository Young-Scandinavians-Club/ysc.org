defmodule Ysc.Encrypted.Binary do
  @moduledoc """
  Ecto type for encrypted binary fields.

  Provides an Ecto type wrapper around Cloak's binary encryption, using
  the Ysc.Vault for encryption/decryption operations.
  """
  use Cloak.Ecto.Binary, vault: Ysc.Vault
end
