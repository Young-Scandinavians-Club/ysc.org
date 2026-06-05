defmodule Ysc.Repo.Migrations.AddReminderRecipientCountToEventPhotoCollections do
  use Ecto.Migration

  def change do
    alter table(:event_photo_collections) do
      add :reminder_recipient_count, :integer
    end
  end
end
