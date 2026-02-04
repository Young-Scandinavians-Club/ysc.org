defmodule Ysc.Repo.Migrations.AddAdvanceBookingDaysToSeasons do
  use Ecto.Migration

  def change do
    alter table(:seasons) do
      # Add new field for configurable advance booking days
      # nil or 0 means no limit, otherwise it's the number of days
      add :advance_booking_days, :integer, null: true
    end
  end
end
