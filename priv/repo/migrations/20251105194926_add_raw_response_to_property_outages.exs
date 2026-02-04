defmodule Ysc.Repo.Migrations.AddRawResponseToPropertyOutages do
  use Ecto.Migration

  def change do
    alter table(:property_outages) do
      add :raw_response, :map
    end
  end
end
