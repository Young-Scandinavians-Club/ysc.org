defmodule Ysc.Repo.Migrations.AddNotificationPreferencesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :newsletter_notifications, :boolean, default: true, null: false
      add :event_notifications, :boolean, default: true, null: false
      add :account_notifications, :boolean, default: true, null: false
    end
  end
end
