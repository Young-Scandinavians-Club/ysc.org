defmodule Ysc.Repo.Migrations.AddArchivedHtmlToNewsletterEditions do
  use Ecto.Migration

  def change do
    alter table(:newsletter_editions) do
      add :archived_html, :text
    end
  end
end
