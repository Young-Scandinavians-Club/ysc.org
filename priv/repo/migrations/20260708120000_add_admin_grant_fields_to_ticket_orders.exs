defmodule Ysc.Repo.Migrations.AddAdminGrantFieldsToTicketOrders do
  use Ecto.Migration

  def change do
    alter table(:ticket_orders) do
      add :granted_by_id,
          references(:users, column: :id, type: :binary_id, on_delete: :nothing),
          null: true

      add :admin_grant_notes, :text, null: true
    end

    create index(:ticket_orders, [:granted_by_id])
  end
end
