defmodule Ysc.Repo.Migrations.CreateBookings do
  use Ecto.Migration

  def change do
    create table(:bookings, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :reference_id, :string, null: false
      add :checkin_date, :date, null: false
      add :checkout_date, :date, null: false
      add :guests_count, :integer, default: 1, null: false
      add :property, :booking_property, null: false
      add :booking_mode, :booking_mode, null: false

      add :room_id, references(:rooms, column: :id, type: :binary_id, on_delete: :nilify_all),
        null: true

      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:bookings, :booking_date_range, check: "checkin_date <= checkout_date")

    create unique_index(:bookings, [:reference_id])
    create index(:bookings, [:property])
    create index(:bookings, [:checkin_date, :checkout_date])
    create index(:bookings, [:room_id])
    create index(:bookings, [:user_id])
  end
end
