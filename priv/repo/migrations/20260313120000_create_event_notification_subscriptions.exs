defmodule Ysc.Repo.Migrations.CreateEventNotificationSubscriptions do
  use Ecto.Migration

  def change do
    create table(:event_notification_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :notification_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:event_notification_subscriptions, [
             :event_id,
             :user_id,
             :notification_type
           ])

    create index(:event_notification_subscriptions, [:event_id, :notification_type])
    create index(:event_notification_subscriptions, [:user_id])
  end
end
