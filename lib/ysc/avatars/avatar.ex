defmodule Ysc.Avatars.Avatar do
  @moduledoc """
  Schema for user avatar images.

  Each record represents a single avatar image (uploaded by the user or synced
  from an OAuth provider). Users accumulate a library of avatars over time and
  can select any previous avatar as their current one.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "avatars" do
    belongs_to :user, Ysc.Accounts.User

    field :source, Ecto.Enum, values: [:upload, :google, :facebook]
    field :original_path, :string
    field :thumb_path, :string
    field :profile_path, :string
    field :large_path, :string

    field :processing_state, Ecto.Enum,
      values: [:pending, :processing, :completed, :failed],
      default: :pending

    field :source_url, :string

    timestamps()
  end

  def create_changeset(avatar, attrs) do
    avatar
    |> cast(attrs, [:source, :original_path, :source_url])
    |> validate_required([:source, :original_path])
    |> validate_inclusion(:source, [:upload, :google, :facebook])
    |> validate_length(:original_path, max: 2048)
    |> validate_length(:source_url, max: 2048)
  end

  def processing_changeset(avatar, attrs) do
    avatar
    |> cast(attrs, [
      :thumb_path,
      :profile_path,
      :large_path,
      :processing_state,
      :original_path
    ])
    |> validate_length(:thumb_path, max: 2048)
    |> validate_length(:profile_path, max: 2048)
    |> validate_length(:large_path, max: 2048)
  end
end
