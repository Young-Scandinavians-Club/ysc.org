defmodule Ysc.Repo.Migrations.AddUpdatedByToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :updated_by_id,
          references(:users, on_delete: :nilify_all, column: :id, type: :binary_id),
          null: true
    end

    create index(:posts, [:updated_by_id])
  end
end
