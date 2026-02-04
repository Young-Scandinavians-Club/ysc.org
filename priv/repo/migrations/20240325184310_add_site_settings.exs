defmodule Ysc.Repo.Migrations.AddSiteSettings do
  use Ecto.Migration

  def change do
    create table(:site_settings, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :group, :string
      add :name, :string, null: false

      add :value, :string

      timestamps()
    end

    create unique_index(:site_settings, [:name])
  end
end
