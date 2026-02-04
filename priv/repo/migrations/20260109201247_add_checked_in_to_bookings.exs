defmodule Ysc.Repo.Migrations.AddCheckedInToBookings do
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      add :checked_in, :boolean, default: false, null: false
    end

    create index(:bookings, [:checked_in])
  end
end
