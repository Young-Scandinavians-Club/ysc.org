defmodule Ysc.Repo.Migrations.AddGuestBuyerToTicketOrders do
  use Ecto.Migration

  def up do
    alter table(:ticket_orders) do
      modify :user_id, :binary_id, null: true, from: {:binary_id, null: false}
      add :guest_email, :string
      add :guest_first_name, :string
      add :guest_last_name, :string
    end

    # Every order has a buyer: a member account, or a guest identified by email.
    create constraint(:ticket_orders, :ticket_orders_buyer_present,
             check: "user_id IS NOT NULL OR guest_email IS NOT NULL"
           )

    create index(:ticket_orders, [:guest_email, :event_id], where: "guest_email IS NOT NULL")
  end

  def down do
    drop index(:ticket_orders, [:guest_email, :event_id])
    drop constraint(:ticket_orders, :ticket_orders_buyer_present)

    alter table(:ticket_orders) do
      remove :guest_last_name
      remove :guest_first_name
      remove :guest_email
      modify :user_id, :binary_id, null: false, from: {:binary_id, null: true}
    end
  end
end
