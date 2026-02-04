defmodule Ysc.Accounts.UserPasskey do
  @moduledoc """
  UserPasskey schema for storing WebAuthn passkey credentials.

  Stores the public key and credential ID for each registered passkey device.
  The private key remains on the user's device and is never transmitted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "user_passkeys" do
    field :external_id, :binary
    field :public_key, :binary
    field :nickname, :string
    field :sign_count, :integer, default: 0
    field :last_used_at, :utc_datetime

    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [
      :external_id,
      :public_key,
      :nickname,
      :sign_count,
      :last_used_at,
      :user_id
    ])
    |> validate_required([:external_id, :public_key, :user_id])
    |> validate_number(:sign_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:external_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for a new passkey.
  """
  def create_changeset(passkey, attrs) do
    changeset(passkey, attrs)
  end

  @doc """
  Creates a changeset for updating sign_count and last_used_at.
  """
  def update_usage_changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:sign_count, :last_used_at])
    |> validate_required([:sign_count])
    |> validate_number(:sign_count, greater_than_or_equal_to: 0)
  end

  @doc """
  Converts a COSE key map to binary for storage.
  """
  def encode_public_key(cose_key_map) when is_map(cose_key_map) do
    :erlang.term_to_binary(cose_key_map)
  end

  @doc """
  Converts binary public key back to COSE key map.

  Uses the `:safe` option to avoid deserializing unsafe terms (funs, pids, refs).
  COSE keys are plain maps and are safe to deserialize.
  """
  # sobelow_skip ["Misc.BinToTerm"]
  def decode_public_key(binary_key) when is_binary(binary_key) do
    :erlang.binary_to_term(binary_key, [:safe])
  end
end
