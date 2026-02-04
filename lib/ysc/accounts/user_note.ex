defmodule Ysc.Accounts.UserNote do
  @moduledoc """
  User note schema and changesets.

  Defines the UserNote database schema for storing admin notes about users.
  Notes are immutable once created.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "user_notes" do
    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    belongs_to :created_by, Ysc.Accounts.User,
      foreign_key: :created_by_user_id,
      references: :id

    field :note, :string
    field :category, UserNoteCategory

    timestamps()
  end

  @doc """
  Creates a changeset for a user note.
  """
  def changeset(user_note, attrs) do
    user_note
    |> cast(attrs, [:user_id, :created_by_user_id, :note, :category])
    |> validate_required([:user_id, :created_by_user_id, :note, :category])
    |> validate_length(:note, min: 1, max: 5000)
  end
end
