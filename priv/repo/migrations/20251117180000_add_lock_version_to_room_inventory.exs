defmodule Ysc.Repo.Migrations.AddLockVersionToRoomInventory do
  use Ecto.Migration

  def change do
    alter table(:room_inventory) do
      add :lock_version, :integer, default: 1, null: false
    end
  end
end
