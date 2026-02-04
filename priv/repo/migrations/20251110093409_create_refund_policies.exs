defmodule Ysc.Repo.Migrations.CreateRefundPolicies do
  use Ecto.Migration

  def change do
    # Create refund_policies table
    create table(:refund_policies, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :name, :text, null: false
      add :description, :text, null: true

      # Property this policy applies to
      add :property, :booking_property, null: false

      # Booking mode this policy applies to (room, day, buyout)
      add :booking_mode, :booking_mode, null: false

      # Whether this policy is currently active
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:refund_policies, [:property, :booking_mode])
    create index(:refund_policies, [:is_active])

    # Create unique index to ensure only one active policy per property/booking_mode combination
    execute(
      """
      CREATE UNIQUE INDEX refund_policies_property_mode_active_unique
      ON refund_policies(property, booking_mode)
      WHERE is_active = true
      """,
      "DROP INDEX IF EXISTS refund_policies_property_mode_active_unique"
    )

    # Create refund_policy_rules table
    create table(:refund_policy_rules, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      # Reference to the parent policy
      add :refund_policy_id,
          references(:refund_policies, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      # Days before check-in date (e.g., 21 means "21 days or less before check-in")
      # Rules are evaluated in descending order of days_before_checkin
      add :days_before_checkin, :integer, null: false

      # Refund percentage (0-100, where 0 = no refund, 100 = full refund)
      add :refund_percentage, :decimal, precision: 5, scale: 2, null: false

      # Optional description for this specific rule
      add :description, :text, null: true

      # Order/priority for this rule (lower number = higher priority)
      # Used to determine evaluation order when multiple rules have same days_before_checkin
      add :priority, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:refund_policy_rules, [:refund_policy_id])
    # Index for efficient rule lookup: policy + days_before_checkin (desc) + priority
    create index(:refund_policy_rules, [:refund_policy_id, :days_before_checkin, :priority])

    # Ensure days_before_checkin is non-negative
    create constraint(:refund_policy_rules, :days_before_checkin_non_negative,
             check: "days_before_checkin >= 0"
           )

    # Ensure refund_percentage is between 0 and 100
    create constraint(:refund_policy_rules, :refund_percentage_range,
             check: "refund_percentage >= 0 AND refund_percentage <= 100"
           )
  end
end
