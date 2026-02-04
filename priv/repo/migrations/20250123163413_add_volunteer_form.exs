defmodule Ysc.Repo.Migrations.AddVolunteerForm do
  use Ecto.Migration

  def change do
    create table(:volunteer_signups, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :email, :text
      add :name, :text

      add :interest_events, :boolean, default: false
      add :interest_activities, :boolean, default: false
      add :interest_clear_lake, :boolean, default: false
      add :interest_tahoe, :boolean, default: false
      add :interest_marketing, :boolean, default: false
      add :interest_website, :boolean, default: false

      timestamps()
    end
  end
end
