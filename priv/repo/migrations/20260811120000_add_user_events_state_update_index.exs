defmodule Ysc.Repo.Migrations.AddUserEventsStateUpdateIndex do
  use Ecto.Migration

  def change do
    create index(:user_events, [:user_id, :type, :inserted_at])
  end
end
