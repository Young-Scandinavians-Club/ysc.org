defmodule Ysc.Repo.Migrations.CreateNewsletterNotices do
  use Ecto.Migration

  def change do
    create table(:newsletter_notices, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :name, :string, null: false
      add :body, :text, null: false

      add :creator_id,
          references(:users, column: :id, type: :binary_id, on_delete: :nilify_all),
          null: true

      timestamps()
    end

    create index(:newsletter_notices, [:creator_id])
    create index(:newsletter_notices, [:name])
  end
end
