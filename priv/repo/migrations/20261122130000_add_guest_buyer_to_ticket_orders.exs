defmodule Ysc.Repo.Migrations.AddGuestBuyerToTicketOrders do
  # Rolling back after guest sales have started
  # -------------------------------------------
  # `down/0` refuses to run while any guest order exists: those rows have no
  # `user_id`, and reassigning them would throw away the only record of who
  # bought (name and email). To back out of public sales:
  #
  #   1. Deploy the previous application version, and set every tier's
  #      "Who can buy" back to a member audience so no new guest orders start.
  #   2. Leave this migration applied. It is additive (a nullable `user_id`,
  #      three new nullable columns and a check constraint), so the previous
  #      version keeps working against it. Guest orders stay readable in the
  #      database for refunds and support.
  #   3. Only revert the schema once the guest orders have been exported and
  #      removed deliberately.
  #
  # Not verified: that the previous application version handles an existing
  # guest order (an order with no user) everywhere it lists orders. Try it on a
  # copy of production data before relying on step 2.
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
