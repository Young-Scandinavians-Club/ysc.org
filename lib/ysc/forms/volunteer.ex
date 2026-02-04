defmodule Ysc.Forms.Volunteer do
  @moduledoc """
  Volunteer signup schema and changesets.

  Defines the Volunteer database schema, validations, and changeset functions
  for volunteer application data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "volunteer_signups" do
    field :email, :string
    field :name, :string

    field :interest_events, :boolean
    field :interest_activities, :boolean
    field :interest_clear_lake, :boolean
    field :interest_tahoe, :boolean
    field :interest_marketing, :boolean
    field :interest_website, :boolean

    belongs_to :user, User, foreign_key: :user_id, references: :id

    timestamps()
  end

  @doc false
  def changeset(volunteer, attrs) do
    volunteer
    |> cast(attrs, [
      :email,
      :name,
      :interest_events,
      :interest_activities,
      :interest_clear_lake,
      :interest_tahoe,
      :interest_marketing,
      :interest_website,
      :user_id
    ])
    |> validate_required([:email, :name])
    # Basic email validation
    |> validate_format(:email, ~r/@/)
  end
end
