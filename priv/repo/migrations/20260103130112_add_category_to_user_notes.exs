defmodule Ysc.Repo.Migrations.AddCategoryToUserNotes do
  use Ecto.Migration

  def change do
    alter table(:user_notes) do
      add :category, :string, null: false, default: "general"
    end

    create index(:user_notes, [:category])
  end
end
