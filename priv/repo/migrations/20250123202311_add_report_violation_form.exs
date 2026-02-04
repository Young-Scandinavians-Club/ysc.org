defmodule Ysc.Repo.Migrations.AddReportViolationForm do
  use Ecto.Migration

  def change do
    create table(:conduct_violation_reports, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :email, :citext, null: false

      add :first_name, :text, null: false
      add :last_name, :text, null: false
      add :phone, :text, null: false

      add :summary, :text, null: false

      add :status, :string, null: false, default: "submitted"

      timestamps()
    end
  end
end
