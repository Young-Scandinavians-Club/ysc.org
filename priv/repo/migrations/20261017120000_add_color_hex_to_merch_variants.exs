defmodule Ysc.Repo.Migrations.AddColorHexToMerchVariants do
  use Ecto.Migration

  def change do
    alter table(:merch_variants) do
      # The color's real hex from Printful's catalog, for the shop's color dots.
      add :color_hex, :string
    end
  end
end
