defmodule Ysc.Repo.Migrations.AddExpiredToBookingEntitlementStatus do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    execute("ALTER TYPE booking_entitlement_status ADD VALUE IF NOT EXISTS 'expired'")
  end

  def down do
    # PostgreSQL does not support removing enum values safely.
  end
end
