defmodule Ysc.Repo.Migrations.CreateEventUpdates do
  use Ecto.Migration

  def change do
    create table(:event_updates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :sent_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :title, :string
      add :raw_body, :text, null: false
      add :rendered_body, :text, null: false
      add :show_on_event_page, :boolean, default: false, null: false
      add :sent_at, :utc_datetime
      add :recipient_count, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:event_updates, [:event_id])
    create index(:event_updates, [:event_id, :show_on_event_page])
  end
end
