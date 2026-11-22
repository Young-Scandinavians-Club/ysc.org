defmodule Ysc.Repo.Migrations.AddSaleAudienceToTicketTiers do
  use Ecto.Migration

  def up do
    alter table(:ticket_tiers) do
      add :sale_audience, :string, null: false, default: "member_guests"
    end

    execute "UPDATE ticket_tiers SET sale_audience = 'members_only' WHERE member_only = true"

    create constraint(:ticket_tiers, :sale_audience_valid,
             check: "sale_audience IN ('members_only', 'member_guests', 'public')"
           )
  end

  def down do
    drop constraint(:ticket_tiers, :sale_audience_valid)

    alter table(:ticket_tiers) do
      remove :sale_audience
    end
  end
end
