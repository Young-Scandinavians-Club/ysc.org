defmodule Ysc.Repo.Migrations.AddUpdatedByToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :updated_by_id,
          references(:users, on_delete: :nilify_all, column: :id, type: :binary_id),
          null: true
    end

    create index(:events, [:updated_by_id])
  end
end
