defmodule Ysc.OAuth.AuthCode do
  @moduledoc """
  One-time authorization code for confidential OAuth clients (PKCE S256).

  Only the SHA-256 hash of the raw code is stored. Shared by all registered
  apps under `Ysc.OAuth` (Query Console today; additional clients later).
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "oauth_auth_codes" do
    field :hashed_code, :binary
    field :client_id, :string
    field :redirect_uri, :string
    field :code_challenge, :string
    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime

    belongs_to :user, Ysc.Accounts.User

    timestamps(updated_at: false)
  end
end
