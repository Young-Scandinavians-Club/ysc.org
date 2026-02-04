defmodule Ysc.Accounts.UserEvent do
  @moduledoc """
  User event schema and changesets.

  Defines the UserEvent database schema for tracking user-related events and changes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "user_events" do
    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    belongs_to :updated_by, Ysc.Accounts.User,
      foreign_key: :updated_by_user_id,
      references: :id

    field :type, UserEventType

    field :from, :string
    field :to, :string

    timestamps()
  end

  def new_user_event_changeset(event, attrs, _opts \\ []) do
    event
    |> cast(attrs, [:user_id, :updated_by_user_id, :type, :from, :to])
    |> validate_required([:user_id, :updated_by_user_id, :type, :from, :to])
  end
end
