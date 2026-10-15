defmodule Ysc.Repo.Migrations.CreateMerchCartItems do
  use Ecto.Migration

  def change do
    create table(:merch_cart_items, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id,
          references(:users, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :variant_id,
          references(:merch_variants, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :quantity, :integer, null: false

      timestamps()
    end

    create unique_index(:merch_cart_items, [:user_id, :variant_id])
    create index(:merch_cart_items, [:variant_id])
  end
end
