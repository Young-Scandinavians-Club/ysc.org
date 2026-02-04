defmodule Ysc.Repo.Migrations.AddCertificationAcceptedToExpenseReports do
  use Ecto.Migration

  def change do
    alter table(:expense_reports) do
      add :certification_accepted, :boolean, default: false, null: false
    end
  end
end
