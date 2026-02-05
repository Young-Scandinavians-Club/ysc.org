defmodule Ysc.Repo.Migrations.AddPartifulLinkToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :partiful_link, :text, null: true
    end
  end
end
