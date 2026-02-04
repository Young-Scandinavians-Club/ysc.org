defmodule Ysc.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :name, :text, null: false
      add :ends_at, :utc_datetime
      add :trial_ends_at, :utc_datetime

      add :stripe_id, :text
      add :stripe_status, :text

      add :start_date, :utc_datetime, null: true
      add :current_period_start, :utc_datetime, null: true
      add :current_period_end, :utc_datetime, null: true

      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:stripe_id])
    create index(:subscriptions, [:user_id, :stripe_status])

    create table(:subscription_items, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :subscription_id, references(:subscriptions, on_delete: :delete_all, type: :binary_id),
        null: false

      add :stripe_id, :text, null: false
      add :stripe_product_id, :text, null: false
      add :stripe_price_id, :text, null: false
      add :quantity, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscription_items, [:stripe_id])
    create index(:subscription_items, [:subscription_id])
  end
end
