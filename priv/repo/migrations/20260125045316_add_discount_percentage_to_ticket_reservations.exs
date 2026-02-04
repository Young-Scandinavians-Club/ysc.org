defmodule Ysc.Repo.Migrations.AddDiscountPercentageToTicketReservations do
  use Ecto.Migration

  def change do
    alter table(:ticket_reservations) do
      add :discount_percentage, :decimal, precision: 5, scale: 2, null: true
    end

    create constraint(:ticket_reservations, :discount_percentage_range,
             check:
               "discount_percentage IS NULL OR (discount_percentage >= 0 AND discount_percentage <= 100)"
           )
  end
end
