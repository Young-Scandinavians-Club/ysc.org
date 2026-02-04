defmodule Ysc.Repo.Migrations.AddPaymentMethod do
  use Ecto.Migration

  def change do
    create table(:payment_methods, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :provider, :text, null: false
      add :provider_id, :text, null: false
      add :provider_customer_id, :text, null: false

      add :type, :text, null: false
      add :provider_type, :text, null: false

      add :last_four, :string, null: true
      add :display_brand, :text, null: true

      add :exp_month, :integer, null: true
      add :exp_year, :integer, null: true

      add :account_type, :text, null: true
      add :routing_number, :text, null: true
      add :bank_name, :text, null: true

      add :user_id, references(:users, column: :id, type: :binary_id), null: false

      add :payload, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:payment_methods, [:provider, :provider_id])

    create index(:payment_methods, [:user_id])
    create index(:payment_methods, [:provider_customer_id])

    alter table(:users) do
      add :default_membership_payment_method,
          references(:payment_methods, column: :id, type: :binary_id),
          null: true
    end
  end
end
