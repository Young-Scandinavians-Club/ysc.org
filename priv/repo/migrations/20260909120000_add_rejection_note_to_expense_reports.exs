defmodule Ysc.Repo.Migrations.AddRejectionNoteToExpenseReports do
  use Ecto.Migration

  # When a treasurer rejects an expense report they must record a note explaining
  # what needs to change. The member is shown this note in-app and by email, then
  # fixes the issues and submits a corrected expense report.
  def change do
    alter table(:expense_reports) do
      add :rejection_note, :text
    end
  end
end
