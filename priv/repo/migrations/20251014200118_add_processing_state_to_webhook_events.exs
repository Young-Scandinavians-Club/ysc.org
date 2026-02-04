defmodule Ysc.Repo.Migrations.AddProcessingStateToWebhookEvents do
  use Ecto.Migration

  def change do
    # Add the "processing" state to the webhook_events state enum
    alter table(:webhook_events) do
      modify :state, :string, default: "pending"
    end

    # Add check constraint to include "processing" state
    create constraint(:webhook_events, :webhook_events_state_check,
             check: "state IN ('pending', 'processing', 'processed', 'failed')"
           )
  end
end
