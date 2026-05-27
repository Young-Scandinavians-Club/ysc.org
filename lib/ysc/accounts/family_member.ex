defmodule Ysc.Accounts.FamilyMember do
  @moduledoc """
  Family member schema and changesets.

  Defines the FamilyMember database schema, validations, and changeset functions
  for family member data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "family_members" do
    field :first_name, :string
    field :last_name, :string
    field :birth_date, :date
    field :type, FamilyMemberType

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    timestamps()
  end

  def family_member_changeset(family_member, attrs, _opts \\ []) do
    family_member
    |> cast(attrs, [:first_name, :last_name, :birth_date, :type])
    |> validate_length(:first_name, min: 1, max: 160)
    |> validate_length(:last_name, min: 1, max: 160)
    |> validate_required([:first_name, :last_name, :type])
    |> validate_birth_date()
  end

  # Validate that birth_date is reasonable (not too old, not in the future)
  defp validate_birth_date(changeset) do
    case get_field(changeset, :birth_date) do
      nil ->
        changeset

      date ->
        today = Date.utc_today()
        # Reasonable minimum birth date
        min_date = Date.new!(1900, 1, 1)
        # Can't be born in the future
        max_date = today

        cond do
          Date.before?(date, min_date) ->
            add_error(changeset, :birth_date, "must be after 1900")

          Date.after?(date, max_date) ->
            add_error(changeset, :birth_date, "cannot be in the future")

          true ->
            changeset
        end
    end
  end
end
