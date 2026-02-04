defmodule Ysc.Repo.Migrations.AddEventIdToExpenseReports do
  use Ecto.Migration

  def change do
    alter table(:expense_reports) do
      add :event_id, references(:events, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:expense_reports, [:event_id])
  end
end
