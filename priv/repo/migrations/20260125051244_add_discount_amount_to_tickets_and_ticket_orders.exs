defmodule Ysc.Repo.Migrations.AddDiscountAmountToTicketsAndTicketOrders do
  use Ecto.Migration

  def change do
    # Add discount_amount to tickets table
    alter table(:tickets) do
      add :discount_amount, :money_with_currency, null: true
    end

    # Add discount_amount to ticket_orders table
    alter table(:ticket_orders) do
      add :discount_amount, :money_with_currency, null: true
    end
  end
end
