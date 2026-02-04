defmodule Ysc.Accounts.SignupApplication do
  @moduledoc """
  Signup application schema and changesets.

  Defines the SignupApplication database schema, validations, and changeset functions
  for user registration application data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ysc.ChangesetHelpers

  @eligibility_options [
    {
      "I am a citizen of a Scandinavian country (Denmark, Finland, Iceland, Norway & Sweden)",
      "citizen_of_scandinavia"
    },
    {"I was born in Scandinavia", "born_in_scandinavia"},
    {
      "I have at least one Scandinavian-born parent, grandparent or great-grandparent",
      "scandinavian_parent"
    },
    {
      "I have lived in Scandinavia for at least six (6) months",
      "lived_in_scandinavia"
    },
    {"I speak one of the Scandinavian languages",
     "speak_scandinavian_language"},
    {"I am the spouse of a member", "spouse_of_member"}
  ]
  @valid_eligibility_option Enum.map(@eligibility_options, fn {_text, val} ->
                              String.to_atom(val)
                            end)
  @eligibility_lookup Enum.reduce(@eligibility_options, %{}, fn {text, val},
                                                                acc ->
                        Map.put(acc, String.to_atom(val), text)
                      end)

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "signup_applications" do
    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    field :membership_type, MembershipType
    field :membership_eligibility, {:array, MembershipEligibility}, default: []

    # has_many :family_members, Ysc.Accounts.FamilyMember

    field :occupation, :string
    field :birth_date, :date

    field :address, :string
    field :country, :string
    field :city, :string
    field :region, :string
    field :postal_code, :string

    field :place_of_birth, :string
    field :citizenship, :string
    field :most_connected_nordic_country, :string

    field :link_to_scandinavia, :string
    field :lived_in_scandinavia, :string
    field :spoken_languages, :string
    field :hear_about_the_club, :string

    field :agreed_to_bylaws, :boolean
    field :agreed_to_bylaws_at, :utc_datetime

    field :started, :utc_datetime
    field :completed, :utc_datetime
    field :browser_timezone, :string

    field :reviewed_at, :utc_datetime
    field :review_outcome, UserApplicationReviewOutcome

    belongs_to :reviewed_by, Ysc.Accounts.User,
      foreign_key: :reviewed_by_user_id,
      references: :id

    timestamps()
  end

  @spec application_changeset(
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
  def application_changeset(application, attrs, _opts \\ []) do
    application
    |> cast(attrs, [
      :user_id,
      :membership_type,
      :membership_eligibility,
      :occupation,
      :birth_date,
      :address,
      :country,
      :city,
      :region,
      :postal_code,
      :place_of_birth,
      :citizenship,
      :most_connected_nordic_country,
      :link_to_scandinavia,
      :lived_in_scandinavia,
      :spoken_languages,
      :hear_about_the_club,
      :agreed_to_bylaws,
      :started,
      :completed,
      :browser_timezone,
      :reviewed_at,
      :review_outcome,
      :reviewed_by_user_id
    ])
    |> validate_required([
      :membership_type,
      :birth_date,
      :address,
      :country,
      :city,
      :postal_code,
      :place_of_birth,
      :citizenship,
      :most_connected_nordic_country
    ])
    |> validate_agreed_to_bylaws()
    |> validate_membership_eligibility()
  end

  def review_outcome_changeset(application, attrs, _opts \\ []) do
    application
    |> cast(attrs, [
      :reviewed_at,
      :review_outcome,
      :reviewed_by_user_id
    ])
    |> validate_required([
      :reviewed_at,
      :review_outcome,
      :reviewed_by_user_id
    ])
  end

  defp validate_agreed_to_bylaws(changeset) do
    case get_change(changeset, :agreed_to_bylaws) do
      true -> changeset
      _ -> add_error(changeset, :agreed_to_bylaws, "must be accepted")
    end
  end

  defp validate_membership_eligibility(changeset) do
    changeset
    |> clean_and_validate_array(
      :membership_eligibility,
      @valid_eligibility_option
    )
    |> validate_length(:membership_eligibility, min: 1)
  end

  @spec eligibility_options() :: [{<<_::64, _::_*8>>, <<_::64, _::_*8>>}, ...]
  def eligibility_options, do: @eligibility_options
  def eligibility_lookup, do: @eligibility_lookup
end
