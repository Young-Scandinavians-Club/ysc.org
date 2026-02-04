defmodule Ysc.Repo.Migrations.CreateCheckIns do
  use Ecto.Migration

  def change do
    create table(:check_ins, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :rules_agreed, :boolean, null: false, default: false
      add :checked_in_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:check_ins, [:checked_in_at])
  end
end
