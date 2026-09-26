defmodule Ysc.Repo.Migrations.ClarifyTahoeRoomMinPriceDescription do
  @moduledoc """
  Room 4's stored description said "Minimum 2 guests required." Members can
  still book that room with one person; the 2-guest figure is a price floor.
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE rooms
    SET description = replace(
          description,
          'Minimum 2 guests required.',
          'Priced for 2 or more guests.'
        ),
        updated_at = NOW() AT TIME ZONE 'utc'
    WHERE property = 'tahoe'
      AND description LIKE '%Minimum 2 guests required.%'
    """)
  end

  def down do
    execute("""
    UPDATE rooms
    SET description = replace(
          description,
          'Priced for 2 or more guests.',
          'Minimum 2 guests required.'
        ),
        updated_at = NOW() AT TIME ZONE 'utc'
    WHERE property = 'tahoe'
      AND description LIKE '%Priced for 2 or more guests.%'
    """)
  end
end
