defmodule Ysc.Repo.Migrations.AddModificationHoldToBookings do
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      add :modification_hold_expires_at, :utc_datetime
      add :modification_hold_attrs, :map
    end

    create index(:bookings, [:modification_hold_expires_at],
             where: "modification_hold_expires_at IS NOT NULL"
           )
  end
end
