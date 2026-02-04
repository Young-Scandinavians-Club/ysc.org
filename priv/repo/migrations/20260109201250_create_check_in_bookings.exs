defmodule Ysc.Repo.Migrations.CreateCheckInBookings do
  use Ecto.Migration

  def change do
    create table(:check_in_bookings, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :check_in_id,
          references(:check_ins, column: :id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :booking_id,
          references(:bookings, column: :id, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:check_in_bookings, [:check_in_id, :booking_id])
    create index(:check_in_bookings, [:check_in_id])
    create index(:check_in_bookings, [:booking_id])
  end
end
