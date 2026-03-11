defmodule Ysc.Repo.Migrations.AddImagesInsertedAtIdIndex do
  use Ecto.Migration

  def change do
    create index(:images, [:inserted_at, :id])
  end
end
