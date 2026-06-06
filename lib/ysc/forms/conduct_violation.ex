defmodule Ysc.Forms.ConductViolationReport do
  @moduledoc """
  Conduct violation report schema and changesets.

  Defines the ConductViolationReport database schema, validations, and changeset functions
  for conduct violation report data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "conduct_violation_reports" do
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :phone, :string

    field :summary, :string
    field :anonymous, :boolean, default: false

    field :status, ViolationFormStatus

    belongs_to :user, User, foreign_key: :user_id, references: :id

    timestamps()
  end

  @user_submittable_fields [
    :email,
    :first_name,
    :last_name,
    :phone,
    :summary,
    :anonymous
  ]

  @doc false
  def changeset(volunteer, attrs) do
    volunteer
    |> cast(attrs, @user_submittable_fields)
    |> validate_required([:email, :first_name, :last_name, :phone, :summary])
    # Basic email validation
    |> validate_format(:email, ~r/@/)
    |> put_change(:status, :submitted)
  end

  @doc """
  Applies the submitting user's id after public params are validated.
  """
  def put_submitter(changeset, %User{id: user_id}) do
    put_change(changeset, :user_id, user_id)
  end

  def put_submitter(changeset, _), do: changeset
end
