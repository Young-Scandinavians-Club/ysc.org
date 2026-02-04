defmodule Ysc.Repo.Migrations.CreateBookingGuests do
  use Ecto.Migration

  def change do
    create table(:booking_guests, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :booking_id,
          references(:bookings, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :first_name, :string, null: false, size: 150
      add :last_name, :string, null: false, size: 150
      add :is_child, :boolean, default: false, null: false
      add :is_booking_user, :boolean, default: false, null: false
      add :order_index, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:booking_guests, [:booking_id])
    create index(:booking_guests, [:order_index])
    create index(:booking_guests, [:booking_id, :order_index])
  end
end
