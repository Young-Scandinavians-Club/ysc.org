defmodule Ysc.Repo.Migrations.ChangeSiteSettingsValueToText do
  use Ecto.Migration

  def change do
    alter table(:site_settings) do
      modify :value, :text
    end
  end
end
