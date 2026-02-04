defmodule Ysc.Repo.Migrations.AddChildrenCountToBookings do
  use Ecto.Migration

  def change do
    alter table(:bookings) do
      add :children_count, :integer, default: 0, null: false
    end
  end
end
