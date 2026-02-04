defmodule Ysc.Repo.Migrations.AddPaymentMethodIdToPayments do
  use Ecto.Migration

  def change do
    alter table(:payments) do
      add :payment_method_id, references(:payment_methods, column: :id, type: :binary_id),
        null: true
    end

    create index(:payments, [:payment_method_id])
  end
end
