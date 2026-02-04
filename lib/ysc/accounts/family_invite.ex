defmodule Ysc.Accounts.FamilyInvite do
  @moduledoc """
  Family invite schema and changesets.

  Defines the FamilyInvite database schema for tracking family member invitations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User

  @rand_size 32
  @invite_validity_in_days 30

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "family_invites" do
    field :email, :string
    field :token, :string
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :primary_user, User, foreign_key: :primary_user_id
    belongs_to :created_by_user, User, foreign_key: :created_by_user_id

    timestamps()
  end

  @doc """
  Generates a secure token for the invite link.
  """
  def build_token do
    token = :crypto.strong_rand_bytes(@rand_size)
    Base.url_encode64(token, padding: false)
  end

  @doc """
  Creates a changeset for a family invite.
  """
  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:email, :token, :primary_user_id, :created_by_user_id])
    |> validate_required([
      :email,
      :token,
      :primary_user_id,
      :created_by_user_id
    ])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint(:token)
    |> put_expires_at()
  end

  defp put_expires_at(changeset) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@invite_validity_in_days, :day)
      |> DateTime.truncate(:second)

    put_change(changeset, :expires_at, expires_at)
  end

  @doc """
  Marks an invite as accepted.
  """
  def accept_changeset(invite) do
    change(invite, accepted_at: DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc """
  Checks if an invite is valid (not expired and not already accepted).
  """
  def valid?(invite) do
    cond do
      not is_nil(invite.accepted_at) -> false
      DateTime.compare(invite.expires_at, DateTime.utc_now()) == :lt -> false
      true -> true
    end
  end
end
