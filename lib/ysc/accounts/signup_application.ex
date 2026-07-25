defmodule Ysc.Accounts.SignupApplication do
  @moduledoc """
  Signup application schema and changesets.

  Defines the SignupApplication database schema, validations, and changeset functions
  for user registration application data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ysc.ChangesetHelpers

  require Ysc.Logging

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

    belongs_to :family_invite, Ysc.Accounts.FamilyInvite,
      foreign_key: :family_invite_id,
      references: :id

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

  @registration_fields [
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
    :browser_timezone
  ]

  @timestamp_fields [
    :started,
    :completed
  ]

  @privileged_fields [
    :user_id,
    :family_invite_id,
    :reviewed_at,
    :review_outcome,
    :reviewed_by_user_id
  ]

  @doc """
  Changeset for public membership registration (LiveView / `register_user/1`).

  Does not cast admin review fields, `user_id`, `family_invite_id`, `started`, or
  `completed` — those must be set only by trusted server code (`register_user/1`).
  """
  def registration_application_changeset(application, attrs, opts \\ []) do
    application
    |> cast(attrs, @registration_fields)
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
    |> validate_birth_date()
    |> validate_agreed_to_bylaws()
    |> validate_membership_eligibility()
    |> validate_scandinavia_connection_fields()
    |> validate_user_email(opts)
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
            },
          opts :: Keyword.t()
        ) :: Ecto.Changeset.t()
  def application_changeset(application, attrs, opts \\ []) do
    application
    |> cast(
      attrs,
      @registration_fields ++ @timestamp_fields ++ @privileged_fields
    )
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
    |> validate_birth_date()
    |> validate_agreed_to_bylaws()
    |> validate_membership_eligibility()
    |> validate_scandinavia_connection_fields()
    |> validate_user_email(opts)
  end

  @doc """
  Changeset for migrating existing WP application data.

  Uses the same field list as `application_changeset/3` (default `opts \\ []`) but skips validations
  that are only meaningful for new signups: required fields (old members often
  have incomplete records), `agreed_to_bylaws` (they agreed under a previous
  system), and `validate_membership_eligibility` (eligibility strings may not
  map cleanly to current enum values).
  """
  def migration_changeset(application, attrs) do
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
      :agreed_to_bylaws_at,
      :started,
      :completed,
      :reviewed_at,
      :review_outcome,
      :reviewed_by_user_id
    ])
    |> validate_birth_date()
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

  defp validate_birth_date(changeset) do
    case get_field(changeset, :birth_date) do
      nil ->
        changeset

      date ->
        today = Date.utc_today()
        min_date = Date.new!(1900, 1, 1)

        cond do
          Date.before?(date, min_date) ->
            add_error(changeset, :birth_date, "must be after 1900")

          Date.after?(date, today) ->
            add_error(changeset, :birth_date, "cannot be in the future")

          true ->
            changeset
        end
    end
  end

  defp validate_agreed_to_bylaws(changeset) do
    case get_change(changeset, :agreed_to_bylaws) do
      true ->
        changeset

      _ ->
        add_error(
          changeset,
          :agreed_to_bylaws,
          "Please check the box to confirm you agree to the bylaws"
        )
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

  @scandinavia_connection_fields [
    :link_to_scandinavia,
    :lived_in_scandinavia,
    :spoken_languages
  ]

  defp validate_scandinavia_connection_fields(changeset) do
    any_present? =
      Enum.any?(@scandinavia_connection_fields, fn field ->
        case get_field(changeset, field) do
          nil -> false
          value -> String.trim(value) != ""
        end
      end)

    if any_present? do
      changeset
    else
      Enum.reduce(@scandinavia_connection_fields, changeset, fn field, cs ->
        add_error(
          cs,
          field,
          "Please fill in at least one of these three fields"
        )
      end)
    end
  end

  defp validate_user_email(changeset, opts) do
    # Only validate emails in production environment to prevent blocking legitimate
    # signups due to email validation errors in dev/sandbox environments.
    if should_validate_email?(opts) do
      case get_field(changeset, :user_id) do
        nil ->
          # No user_id means we can't validate the email
          changeset

        user_id ->
          # Fetch the user's email and validate it
          validate_email_for_user(changeset, user_id)
      end
    else
      changeset
    end
  end

  defp should_validate_email?(opts) do
    # Allow override via opts (useful for testing)
    case Keyword.get(opts, :validate_email) do
      true ->
        true

      false ->
        false

      nil ->
        # Default: only validate in production environment
        production_environment?()
    end
  end

  defp production_environment? do
    case Application.get_env(:ysc, :environment, "dev") do
      env when env in ["production", "prod", :production, :prod] -> true
      _ -> false
    end
  end

  defp validate_email_for_user(changeset, user_id) do
    # Defensive: If we can't fetch the user or email, fail open (don't block signup)
    try do
      {micros, user} =
        :timer.tc(fn -> Ysc.Repo.get(Ysc.Accounts.User, user_id) end)

      duration_ms = div(micros + 500, 1000)

      :telemetry.execute(
        [:ysc, :accounts, :signup_application, :validate_email_user_lookup],
        %{duration: duration_ms, count: 1},
        %{user_id: user_id, result: if(user, do: :ok, else: :not_found)}
      )

      case user do
        nil ->
          Ysc.Logging.error(
            "Signup application email validation skipped: user not found (fail open)",
            error: :user_not_found,
            extra: %{user_id: user_id},
            tags: %{feature: "signup_application_email_validation"}
          )

          changeset

        user ->
          case Ysc.Newsletter.EmailValidator.validate_email(user.email) do
            :ok ->
              changeset

            {:error, :disposable_email} = err ->
              Ysc.Logging.error(
                "Signup application email validation failed",
                error: err,
                extra: %{
                  user_id: user_id,
                  email: user.email,
                  reason: :disposable_email
                },
                tags: %{feature: "signup_application_email_validation"}
              )

              add_error(
                changeset,
                :base,
                "Email address appears to be a temporary or disposable email. Please use a permanent email address."
              )

            {:error, :no_mx_records} = err ->
              Ysc.Logging.error(
                "Signup application email validation failed",
                error: err,
                extra: %{
                  user_id: user_id,
                  email: user.email,
                  reason: :no_mx_records
                },
                tags: %{feature: "signup_application_email_validation"}
              )

              add_error(
                changeset,
                :base,
                "Email domain cannot receive mail. Please check your email address."
              )

            {:error, :invalid_email} = err ->
              Ysc.Logging.error(
                "Signup application email validation failed",
                error: err,
                extra: %{
                  user_id: user_id,
                  email: user.email,
                  reason: :invalid_email
                },
                tags: %{feature: "signup_application_email_validation"}
              )

              add_error(changeset, :base, "Email address is invalid")

            other ->
              Ysc.Logging.error(
                "Signup application email validation unknown result (fail open)",
                error: {:unknown_validator_result, other},
                extra: %{
                  user_id: user_id,
                  email: user.email,
                  validator_result: inspect(other)
                },
                tags: %{feature: "signup_application_email_validation"}
              )

              changeset
          end
      end
    rescue
      error ->
        email_extra =
          try do
            case Ysc.Repo.get(Ysc.Accounts.User, user_id) do
              %{email: email} -> email
              _ -> nil
            end
          rescue
            _ -> nil
          end

        Ysc.Logging.error(
          "Signup application email validation raised (fail open)",
          error: error,
          stacktrace: __STACKTRACE__,
          extra: %{user_id: user_id, email: email_extra},
          tags: %{feature: "signup_application_email_validation"}
        )

        changeset
    end
  end

  @spec eligibility_options() :: [{<<_::64, _::_*8>>, <<_::64, _::_*8>>}, ...]
  def eligibility_options, do: @eligibility_options
  def eligibility_lookup, do: @eligibility_lookup
end
