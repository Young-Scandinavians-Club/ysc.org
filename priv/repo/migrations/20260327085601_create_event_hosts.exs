defmodule Ysc.Repo.Migrations.CreateEventHosts do
  use Ecto.Migration

  def change do
    create table(:event_hosts, primary_key: false) do
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
    end

    create index(:event_hosts, [:event_id])
    create index(:event_hosts, [:user_id])
    create unique_index(:event_hosts, [:event_id, :user_id])
  end
end
