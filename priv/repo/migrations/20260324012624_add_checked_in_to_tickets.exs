defmodule Ysc.Repo.Migrations.AddCheckedInToTickets do
  use Ecto.Migration

  def change do
    alter table(:tickets) do
      add :checked_in, :boolean, default: false, null: false
      add :checked_in_at, :utc_datetime
    end

    create index(:tickets, [:checked_in])
    create index(:tickets, [:event_id, :checked_in])
  end
end
