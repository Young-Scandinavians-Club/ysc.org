defmodule Ysc.Repo.Migrations.UsersCustomerColumns do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :stripe_id, :text, null: true
    end

    create unique_index(:users, [:stripe_id])
  end
end
