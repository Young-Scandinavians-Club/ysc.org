defmodule Ysc.Repo.Migrations.AddQuickbooksCustomerIdToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :quickbooks_customer_id, :text
    end

    create index(:users, [:quickbooks_customer_id])
  end

  def down do
    drop index(:users, [:quickbooks_customer_id])

    alter table(:users) do
      remove :quickbooks_customer_id
    end
  end
end
