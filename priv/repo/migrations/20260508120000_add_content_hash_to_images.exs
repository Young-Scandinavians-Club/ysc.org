defmodule Ysc.Repo.Migrations.AddContentHashToImages do
  use Ecto.Migration

  def change do
    alter table(:images) do
      add :content_hash, :text
    end

    create unique_index(:images, [:content_hash])
  end
end
