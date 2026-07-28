defmodule Ysc.Repo.Migrations.AddRecipientCountToNewsletterEditions do
  use Ecto.Migration

  def change do
    alter table(:newsletter_editions) do
      add :recipient_count, :integer
    end
  end
end
