defmodule Ysc.Repo.Migrations.AddLockVersionToPropertyInventory do
  use Ecto.Migration

  def change do
    alter table(:property_inventory) do
      add :lock_version, :integer, default: 1, null: false
    end
  end
end
