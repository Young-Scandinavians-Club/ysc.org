defmodule Ysc.Repo.Migrations.CreateCheckInVehicles do
  use Ecto.Migration

  def change do
    create table(:check_in_vehicles, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :check_in_id,
          references(:check_ins, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :type, :string, null: false, size: 100
      add :color, :string, null: false, size: 100
      add :make, :string, null: false, size: 100

      timestamps(type: :utc_datetime)
    end

    create index(:check_in_vehicles, [:check_in_id])
  end
end
