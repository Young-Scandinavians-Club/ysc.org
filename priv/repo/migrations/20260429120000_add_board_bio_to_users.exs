defmodule Ysc.Repo.Migrations.AddBoardBioToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :board_bio, :text
    end
  end
end
