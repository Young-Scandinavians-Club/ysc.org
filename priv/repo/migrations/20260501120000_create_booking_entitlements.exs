defmodule Ysc.Repo.Migrations.CreateBookingEntitlements do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE TYPE booking_entitlement_benefit_kind AS ENUM (
        'free_nights', 'percent_off', 'fixed_amount_off'
      )
      """,
      "DROP TYPE IF EXISTS booking_entitlement_benefit_kind"
    )

    execute(
      """
      CREATE TYPE booking_entitlement_status AS ENUM (
        'active', 'consumed', 'revoked'
      )
      """,
      "DROP TYPE IF EXISTS booking_entitlement_status"
    )

    create table(:booking_entitlements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :issued_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: true

      add :benefit_kind, :booking_entitlement_benefit_kind, null: false
      add :status, :booking_entitlement_status, null: false, default: "active"

      add :property, :booking_property, null: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :nilify_all), null: true

      add :max_guests, :integer, null: true
      add :free_nights, :integer, null: true
      add :percent_off, :numeric, null: true
      add :amount_off, :money_with_currency, null: true
      add :buyout_max_discount, :money_with_currency, null: true

      add :expires_at, :utc_datetime, null: true
      add :consumed_at, :utc_datetime, null: true
      add :internal_note, :text, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:booking_entitlements, [:user_id])
    create index(:booking_entitlements, [:user_id, :status])
    create index(:booking_entitlements, [:status])
    create index(:booking_entitlements, [:expires_at])
    create index(:booking_entitlements, [:property])

    create index(:booking_entitlements, [:status, :expires_at], where: "status = 'active'")

    alter table(:bookings) do
      add :subtotal_price, :money_with_currency, null: true
      add :discount_total, :money_with_currency, null: true

      add :applied_booking_entitlement_id,
          references(:booking_entitlements, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    alter table(:booking_entitlements) do
      add :consumed_booking_id,
          references(:bookings, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    create index(:bookings, [:applied_booking_entitlement_id])
    create index(:booking_entitlements, [:consumed_booking_id])
  end
end
