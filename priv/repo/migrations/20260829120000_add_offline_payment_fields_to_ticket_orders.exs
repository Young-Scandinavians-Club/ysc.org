defmodule Ysc.Repo.Migrations.AddOfflinePaymentFieldsToTicketOrders do
  use Ecto.Migration

  # In-person cash/check ticket sales recorded via the admin app. The order
  # total stays $0 (it is an admin grant, not a charge); these columns capture
  # how the money was actually collected so the treasurer can reconcile.
  def change do
    alter table(:ticket_orders) do
      add :payment_channel, :string, null: true
      add :offline_amount_collected, :money_with_currency, null: true
    end
  end
end
