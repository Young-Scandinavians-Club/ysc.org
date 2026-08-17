defmodule Ysc.Repo.Migrations.AddUpdatedByToNewsletterEditions do
  use Ecto.Migration

  def change do
    alter table(:newsletter_editions) do
      add :updated_by_id,
          references(:users, on_delete: :nilify_all, column: :id, type: :binary_id),
          null: true
    end

    create index(:newsletter_editions, [:updated_by_id])
  end
end
