defmodule Ysc.Repo.Migrations.RemoveInsertedAtFromEventHosts do
  use Ecto.Migration

  def change do
    alter table(:event_hosts) do
      remove :inserted_at
    end
  end
end
