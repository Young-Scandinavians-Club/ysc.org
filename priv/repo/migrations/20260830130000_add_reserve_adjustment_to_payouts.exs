defmodule Ysc.Repo.Migrations.AddReserveAdjustmentToPayouts do
  use Ecto.Migration

  # Net of Stripe `payout_minimum_balance_hold` / `payout_minimum_balance_release`
  # balance transactions attributed to a payout. Negative when Stripe withholds
  # funds as a minimum-balance reserve this cycle, positive when it releases a
  # previously withheld reserve. Needed so payout reconciliation can account for
  # the difference between (payments - refunds - fees) and the amount actually
  # wired to the bank.
  def change do
    alter table(:payouts) do
      add :reserve_adjustment, :money_with_currency
    end
  end
end
