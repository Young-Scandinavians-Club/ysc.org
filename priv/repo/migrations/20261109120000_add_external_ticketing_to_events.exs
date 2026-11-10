defmodule Ysc.Repo.Migrations.AddExternalTicketingToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      # Events we list for other organizations: tickets are sold on their site.
      add :external_ticket_url, :text, null: true
      add :external_organizer, :string, null: true
    end
  end
end
