defmodule Ysc.Repo.Migrations.RemoveNewsletterNotificationsFromUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :newsletter_notifications
    end
  end
end
