defmodule Ysc.Repo.Migrations.AddSignupApplication do
  use Ecto.Migration

  def change do
    create table(:signup_applications, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :user_id, references(:users, column: :id, type: :binary_id), null: false

      add :membership_type, :string, null: false
      add :membership_eligibility, {:array, :string}, null: false
      add :occupation, :text, null: true
      add :birth_date, :date, null: false

      add :address, :text, null: false
      add :country, :text, null: false
      add :city, :text, null: false
      # State, province etc
      add :region, :text, null: true
      add :postal_code, :text, null: false

      add :place_of_birth, :text, null: false
      add :citizenship, :text, null: false

      add :most_connected_nordic_country, :text, null: false

      # Longer questions
      add :link_to_scandinavia, :text
      add :lived_in_scandinavia, :text
      add :spoken_languages, :text
      add :hear_about_the_club, :text

      add :agreed_to_bylaws, :boolean
      add :agreed_to_bylaws_at, :utc_datetime, default: fragment("now()")

      add :started, :utc_datetime, null: true
      add :completed, :utc_datetime, default: fragment("now()")
      add :browser_timezone, :string, null: true

      add :review_outcome, :string, null: true
      add :reviewed_by_user_id, references(:users, column: :id, type: :binary_id), null: true
      add :reviewed_at, :utc_datetime, null: true

      timestamps()
    end

    create unique_index(:signup_applications, [:user_id])

    create table(:family_members, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :first_name, :text, null: false
      add :last_name, :text, null: false
      add :birth_date, :date, null: true
      # Spouse or Child
      add :type, :string, null: false

      add :user_id, references(:users, column: :id, type: :binary_id), null: false

      timestamps()
    end

    create index(:family_members, [:user_id])

    create table(:signup_application_review_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :application_id, references(:signup_applications, column: :id, type: :binary_id),
        null: false

      add :user_id, references(:users, column: :id, type: :binary_id), null: false
      add :reviewer_user_id, references(:users, column: :id, type: :binary_id), null: false

      add :result, :string, null: true

      add :event, :string, null: false

      timestamps()
    end

    create index(:signup_application_review_events, [:application_id])
    create index(:signup_application_review_events, [:user_id])
  end
end
