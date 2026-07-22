defmodule Ysc.VerificationCode do
  @moduledoc """
  Schema for short-lived email/SMS verification codes.

  Codes are encrypted at rest and shared across all app nodes via Postgres,
  so verification works in multi-node production deployments.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "verification_codes" do
    field :user_id, :string
    field :code_type, :string
    field :code, Ysc.Encrypted.Binary
    field :expires_at, :utc_datetime

    timestamps(updated_at: false)
  end

  def changeset(verification_code, attrs) do
    verification_code
    |> cast(attrs, [:user_id, :code_type, :code, :expires_at])
    |> validate_required([:user_id, :code_type, :code, :expires_at])
    |> unique_constraint([:user_id, :code_type])
  end
end
