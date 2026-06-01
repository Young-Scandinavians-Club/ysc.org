defmodule Ysc.Repo.Migrations.AddGooglePhotosConnectionsKeyCheck do
  use Ecto.Migration

  def change do
    create constraint(:google_photos_connections, :only_default_key, check: "key = 'default'")
  end
end
