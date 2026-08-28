defmodule Ysc.Repo.Migrations.AddMemberOnlyToTicketTiers do
  use Ecto.Migration

  def change do
    alter table(:ticket_tiers) do
      add :member_only, :boolean, default: false, null: false
    end
  end
end
