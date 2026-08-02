defmodule Ysc.Repo.Migrations.SeedTahoeWifiSiteSettings do
  use Ecto.Migration

  @network "YSC"
  @password "Timberland"

  def up do
    upsert("tahoe_wifi_network", @network)
    upsert("tahoe_wifi_password", @password)
  end

  def down do
    execute("""
    DELETE FROM site_settings
    WHERE name IN ('tahoe_wifi_network', 'tahoe_wifi_password')
    """)
  end

  defp upsert(name, value) do
    execute("""
    UPDATE site_settings
    SET value = '#{value}', updated_at = NOW() AT TIME ZONE 'utc'
    WHERE name = '#{name}'
    """)

    execute("""
    INSERT INTO site_settings (id, "group", name, value, inserted_at, updated_at)
    SELECT gen_random_uuid(), 'tahoe', '#{name}', '#{value}', NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc'
    WHERE NOT EXISTS (
      SELECT 1 FROM site_settings WHERE name = '#{name}'
    )
    """)
  end
end
