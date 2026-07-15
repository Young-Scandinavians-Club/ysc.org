defmodule Ysc.Repo.Migrations.RenameDiscordToPartifulSiteSetting do
  use Ecto.Migration

  @partiful_url "https://partiful.com/u/nm9TVCDwC3y28CL4fcTX"
  @discord_url "https://discord.gg/dn2gdXRZbW"

  def up do
    execute(
      """
      UPDATE site_settings
      SET name = 'partiful', value = '#{@partiful_url}', updated_at = NOW() AT TIME ZONE 'utc'
      WHERE name = 'discord'
      """,
      """
      UPDATE site_settings
      SET name = 'discord', value = '#{@discord_url}', updated_at = NOW() AT TIME ZONE 'utc'
      WHERE name = 'partiful'
      """
    )

    execute("""
    INSERT INTO site_settings (id, "group", name, value, inserted_at, updated_at)
    SELECT gen_random_uuid(), 'socials', 'partiful', '#{@partiful_url}', NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc'
    WHERE NOT EXISTS (
      SELECT 1 FROM site_settings WHERE name IN ('partiful', 'discord')
    )
    """)
  end

  def down do
    execute(
      """
      UPDATE site_settings
      SET name = 'discord', value = '#{@discord_url}', updated_at = NOW() AT TIME ZONE 'utc'
      WHERE name = 'partiful'
      """,
      """
      UPDATE site_settings
      SET name = 'partiful', value = '#{@partiful_url}', updated_at = NOW() AT TIME ZONE 'utc'
      WHERE name = 'discord'
      """
    )
  end
end
