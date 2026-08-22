defmodule Ysc.Repo.Migrations.AddMileageFieldsToExpenseReportItems do
  use Ecto.Migration

  def change do
    alter table(:expense_report_items) do
      add :expense_type, :text, null: false, default: "purchase"
      add :miles_driven, :integer, null: true
      add :mileage_from_to, :text, null: true
    end

    create constraint(:expense_report_items, :expense_type_must_be_known,
             check: "expense_type IN ('purchase', 'mileage')"
           )

    create index(:expense_report_items, [:expense_type])
  end
end
