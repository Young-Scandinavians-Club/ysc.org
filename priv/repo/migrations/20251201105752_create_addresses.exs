defmodule Ysc.Repo.Migrations.CreateAddresses do
  use Ecto.Migration

  def change do
    create table(:addresses, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :user_id, references(:users, column: :id, type: :binary_id), null: false

      add :address, :text, null: false
      add :city, :text, null: false
      add :region, :text, null: true
      add :postal_code, :text, null: false
      add :country, :text, null: false

      timestamps()
    end

    create unique_index(:addresses, [:user_id])
  end
end
