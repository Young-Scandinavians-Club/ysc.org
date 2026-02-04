defmodule Ysc.Accounts.SignupApplicationEvent do
  @moduledoc """
  Signup application event schema and changesets.

  Defines the SignupApplicationEvent database schema for tracking
  application review and status change events.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "signup_application_review_events" do
    belongs_to :application, Ysc.Accounts.SignupApplication,
      foreign_key: :application_id,
      references: :id

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    belongs_to :reviewer, Ysc.Accounts.User,
      foreign_key: :reviewer_user_id,
      references: :id

    field :result, :string
    field :event, SignupApplicationEventType

    timestamps()
  end

  @spec new_event_changeset(
          {map(), map()}
          | %{
              :__struct__ =>
                atom() | %{:__changeset__ => map(), optional(any()) => any()},
              optional(atom()) => any()
            },
          :invalid
          | %{
              optional(:__struct__) => none(),
              optional(atom() | binary()) => any()
            }
        ) :: Ecto.Changeset.t()
  def new_event_changeset(event, attrs, _opts \\ []) do
    event
    |> cast(attrs, [
      :event,
      :application_id,
      :user_id,
      :reviewer_user_id,
      :result
    ])
    |> validate_required([:event, :application_id, :user_id, :reviewer_user_id])
  end
end
