defmodule Ysc.Repo.Migrations.AddSmsFieldsToEventUpdates do
  use Ecto.Migration

  def change do
    alter table(:event_updates) do
      add :send_sms, :boolean, default: false, null: false
      add :sms_body, :text
      add :sms_recipient_count, :integer
    end
  end
end
