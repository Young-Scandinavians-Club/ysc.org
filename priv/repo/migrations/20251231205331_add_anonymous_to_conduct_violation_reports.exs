defmodule Ysc.Repo.Migrations.AddAnonymousToConductViolationReports do
  use Ecto.Migration

  def change do
    alter table(:conduct_violation_reports) do
      add :anonymous, :boolean, default: false, null: false
    end
  end
end
