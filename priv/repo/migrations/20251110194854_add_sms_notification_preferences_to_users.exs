defmodule Ysc.Repo.Migrations.AddSmsNotificationPreferencesToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :account_notifications_sms, :boolean, default: true, null: false
      add :event_notifications_sms, :boolean, default: true, null: false
    end
  end

  def down do
    alter table(:users) do
      remove :account_notifications_sms
      remove :event_notifications_sms
    end
  end
end
