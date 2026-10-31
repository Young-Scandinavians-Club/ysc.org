defmodule Ysc.Repo.Migrations.CreateMerchCartEvents do
  use Ecto.Migration

  def change do
    # Append-only log of what happens to merch cart lines. `merch_cart_items`
    # only holds the cart as it is now (rows vanish on removal and purchase),
    # so this is what lets the shop dashboard count carts started, items
    # removed and carted lines that were bought.
    create table(:merch_cart_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id,
          references(:users, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :variant_id,
          references(:merch_variants, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      # "added" | "removed" | "purchased"; `quantity` is the units moved, so
      # added - removed - purchased is what is in carts.
      add :action, :string, null: false
      add :quantity, :integer, null: false

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:merch_cart_events, [:inserted_at])
    create index(:merch_cart_events, [:user_id, :inserted_at])
    create index(:merch_cart_events, [:variant_id, :inserted_at])
  end
end
