defmodule Ysc.Repo.Migrations.AddFamilyRelationshipToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :primary_user_id, references(:users, on_delete: :nilify_all, type: :binary_id)
    end

    create index(:users, [:primary_user_id])
  end
end
