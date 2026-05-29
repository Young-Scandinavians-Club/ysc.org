defmodule Ysc.Repo.Migrations.AddRefundForfeitedAtToBookings do
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      add :refund_forfeited_at, :utc_datetime
    end
  end
end
