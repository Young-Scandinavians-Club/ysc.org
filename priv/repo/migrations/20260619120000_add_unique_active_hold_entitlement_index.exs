defmodule Ysc.Repo.Migrations.AddUniqueActiveHoldEntitlementIndex do
  use Ecto.Migration

  def change do
    create unique_index(
             :bookings,
             [:applied_booking_entitlement_id],
             name: :bookings_one_hold_per_entitlement_idx,
             where: "status = 'hold' AND applied_booking_entitlement_id IS NOT NULL"
           )
  end
end
