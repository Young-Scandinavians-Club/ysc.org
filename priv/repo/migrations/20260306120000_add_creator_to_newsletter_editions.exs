defmodule Ysc.Repo.Migrations.AddCreatorToNewsletterEditions do
  use Ecto.Migration

  def change do
    alter table(:newsletter_editions) do
      add :creator_id, references(:users, column: :id, type: :binary_id, on_delete: :nilify_all),
        null: true
    end

    create index(:newsletter_editions, [:creator_id])
  end
end
