defmodule Ysc.Repo.Migrations.AddUserIdToForms do
  use Ecto.Migration

  def change do
    alter table(:volunteer_signups) do
      add :user_id, references(:users, on_delete: :nilify_all, column: :id, type: :binary_id),
        null: true
    end

    create index(:volunteer_signups, [:user_id])

    alter table(:conduct_violation_reports) do
      add :user_id, references(:users, on_delete: :nilify_all, column: :id, type: :binary_id),
        null: true
    end

    create index(:conduct_violation_reports, [:user_id])
  end
end
