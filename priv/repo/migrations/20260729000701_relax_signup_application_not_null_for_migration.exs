defmodule Ysc.Repo.Migrations.RelaxSignupApplicationNotNullForMigration do
  use Ecto.Migration

  # Aligns signup_applications nullability with SignupApplication.migration_changeset/2,
  # which skips required-field validation for incomplete WP-migrated records and
  # post-migration onboarding stubs that only need to persist membership_type.
  # New public registrations still require these via registration_application_changeset/3.

  def up do
    alter table(:signup_applications) do
      modify :birth_date, :date, null: true, from: {:date, null: false}
      modify :address, :text, null: true, from: {:text, null: false}
      modify :country, :text, null: true, from: {:text, null: false}
      modify :city, :text, null: true, from: {:text, null: false}
      modify :postal_code, :text, null: true, from: {:text, null: false}
      modify :place_of_birth, :text, null: true, from: {:text, null: false}
      modify :citizenship, :text, null: true, from: {:text, null: false}

      modify :most_connected_nordic_country, :text,
        null: true,
        from: {:text, null: false}
    end
  end

  def down do
    # Stub / incomplete rows may have NULLs after up/0; backfill before NOT NULL.
    execute("""
    UPDATE signup_applications
    SET
      birth_date = COALESCE(birth_date, DATE '1900-01-01'),
      address = COALESCE(address, ''),
      country = COALESCE(country, ''),
      city = COALESCE(city, ''),
      postal_code = COALESCE(postal_code, ''),
      place_of_birth = COALESCE(place_of_birth, ''),
      citizenship = COALESCE(citizenship, ''),
      most_connected_nordic_country = COALESCE(most_connected_nordic_country, '')
    """)

    alter table(:signup_applications) do
      modify :birth_date, :date, null: false, from: {:date, null: true}
      modify :address, :text, null: false, from: {:text, null: true}
      modify :country, :text, null: false, from: {:text, null: true}
      modify :city, :text, null: false, from: {:text, null: true}
      modify :postal_code, :text, null: false, from: {:text, null: true}
      modify :place_of_birth, :text, null: false, from: {:text, null: true}
      modify :citizenship, :text, null: false, from: {:text, null: true}

      modify :most_connected_nordic_country, :text,
        null: false,
        from: {:text, null: true}
    end
  end
end
