defmodule Ysc.Repo.Migrations.AddSendNotificationToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :send_notification, :boolean, null: false, default: false
    end
  end
end
