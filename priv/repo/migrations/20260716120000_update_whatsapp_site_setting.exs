defmodule Ysc.Repo.Migrations.UpdateWhatsappSiteSetting do
  use Ecto.Migration

  @old_whatsapp_url "https://chat.whatsapp.com/DfTCpY2BHar7mmenrkDACZ"
  @whatsapp_url "https://chat.whatsapp.com/LvsXNcpGPuH2pSTuGGaUwF?s=cl&p=i&ilr=1"

  def up do
    execute(
      """
      UPDATE site_settings
      SET value = '#{@whatsapp_url}', updated_at = NOW() AT TIME ZONE 'utc'
      WHERE name = 'whatsapp'
      """,
      """
      UPDATE site_settings
      SET value = '#{@old_whatsapp_url}', updated_at = NOW() AT TIME ZONE 'utc'
      WHERE name = 'whatsapp'
      """
    )

    execute("""
    INSERT INTO site_settings (id, "group", name, value, inserted_at, updated_at)
    SELECT gen_random_uuid(), 'socials', 'whatsapp', '#{@whatsapp_url}', NOW() AT TIME ZONE 'utc', NOW() AT TIME ZONE 'utc'
    WHERE NOT EXISTS (
      SELECT 1 FROM site_settings WHERE name = 'whatsapp'
    )
    """)
  end

  def down do
    execute(
      """
      UPDATE site_settings
      SET value = '#{@old_whatsapp_url}', updated_at = NOW() AT TIME ZONE 'utc'
      WHERE name = 'whatsapp'
      """,
      """
      UPDATE site_settings
      SET value = '#{@whatsapp_url}', updated_at = NOW() AT TIME ZONE 'utc'
      WHERE name = 'whatsapp'
      """
    )
  end
end
