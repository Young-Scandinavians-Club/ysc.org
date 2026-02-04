defmodule Ysc.Repo.Migrations.AddBedCountsAndImageToRooms do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      # Bed counts
      add :single_beds, :integer, default: 0, null: false
      add :queen_beds, :integer, default: 0, null: false
      add :king_beds, :integer, default: 0, null: false

      # Image association
      add :image_id,
          references(:images, column: :id, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    # Add check constraints to ensure bed counts are non-negative
    create constraint(:rooms, :single_beds_non_negative, check: "single_beds >= 0")
    create constraint(:rooms, :queen_beds_non_negative, check: "queen_beds >= 0")
    create constraint(:rooms, :king_beds_non_negative, check: "king_beds >= 0")

    # Add index for image_id foreign key
    create index(:rooms, [:image_id])
  end
end
