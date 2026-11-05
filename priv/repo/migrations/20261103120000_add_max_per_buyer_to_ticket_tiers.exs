defmodule Ysc.Repo.Migrations.AddMaxPerBuyerToTicketTiers do
  use Ecto.Migration

  def change do
    alter table(:ticket_tiers) do
      add :max_per_buyer, :integer
    end

    create constraint(:ticket_tiers, :max_per_buyer_positive,
             check: "max_per_buyer IS NULL OR max_per_buyer > 0"
           )
  end
end
