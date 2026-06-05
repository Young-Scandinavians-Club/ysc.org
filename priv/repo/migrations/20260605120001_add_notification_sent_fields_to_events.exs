defmodule Ysc.Repo.Migrations.AddNotificationSentFieldsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :notification_sent_at, :utc_datetime
      add :notification_recipient_count, :integer
    end
  end
end
