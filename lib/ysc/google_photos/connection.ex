defmodule Ysc.GooglePhotos.Connection do
  @moduledoc """
  Stores OAuth credentials for the organization's Google Photos account.

  Only one row exists (`key: "default"`). The refresh token is encrypted at rest.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User

  @singleton_key "default"

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "google_photos_connections" do
    field :key, :string, default: @singleton_key
    field :refresh_token, Ysc.Encrypted.Binary
    field :account_email, :string
    field :scopes, :string
    field :connected_at, :utc_datetime

    belongs_to :connected_by, User,
      foreign_key: :connected_by_id,
      references: :id

    timestamps()
  end

  def singleton_key, do: @singleton_key

  @doc false
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :key,
      :refresh_token,
      :account_email,
      :scopes,
      :connected_at
    ])
    |> validate_required([:key, :refresh_token, :connected_at])
    |> unique_constraint(:key)
    |> foreign_key_constraint(:connected_by_id)
  end

  @doc false
  def connect_changeset(connection, attrs, connected_by_id) do
    connection
    |> changeset(attrs)
    |> put_change(:connected_by_id, connected_by_id)
  end
end
