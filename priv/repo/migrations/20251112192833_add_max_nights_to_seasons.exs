defmodule Ysc.Repo.Migrations.AddMaxNightsToSeasons do
  use Ecto.Migration

  def change do
    alter table(:seasons) do
      # Maximum number of nights allowed for bookings in this season
      # nil means use property default (4 for Tahoe, 30 for Clear Lake)
      add :max_nights, :integer, null: true
    end
  end
end
