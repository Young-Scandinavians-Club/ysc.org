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
    # Guest orders have no user, so user_id can't go back to NOT NULL while any
    # exist. Fail with a clear message instead of a constraint error mid-way.
    execute """
            DO $$
            BEGIN
              IF EXISTS (SELECT 1 FROM ticket_orders WHERE user_id IS NULL) THEN
                RAISE EXCEPTION 'Cannot roll back: guest ticket orders exist. Remove or reassign them first.';
              END IF;
            END $$;
            """,
            ""

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
