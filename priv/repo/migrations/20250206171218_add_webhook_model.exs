defmodule Ysc.Repo.Migrations.AddWebhookModel do
  use Ecto.Migration

  def change do
    create table(:webhook_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :provider, :text, null: false
      add :state, :string, default: "pending"
      add :event_id, :text, null: false
      add :event_type, :text, null: false

      add :payload, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:webhook_events, [:provider, :event_id])
    create index(:webhook_events, [:state])
    # Note: event_id is a string (external provider ID), not a foreign key
    # but we add an index for lookup performance
    create index(:webhook_events, [:event_id])
  end
end
