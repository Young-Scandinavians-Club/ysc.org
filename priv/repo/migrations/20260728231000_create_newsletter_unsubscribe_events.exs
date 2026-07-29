defmodule Ysc.Repo.Migrations.CreateNewsletterUnsubscribeEvents do
  use Ecto.Migration

  def change do
    create table(:newsletter_unsubscribe_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :edition_id,
          references(:newsletter_editions,
            column: :id,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :subscriber_id,
          references(:newsletter_subscribers,
            column: :id,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :unsubscribed_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:newsletter_unsubscribe_events, [:edition_id, :subscriber_id])
    create index(:newsletter_unsubscribe_events, [:edition_id])
    create index(:newsletter_unsubscribe_events, [:subscriber_id])
  end
end
