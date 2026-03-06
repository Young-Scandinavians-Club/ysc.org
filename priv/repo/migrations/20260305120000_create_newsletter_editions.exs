defmodule Ysc.Repo.Migrations.CreateNewsletterEditions do
  use Ecto.Migration

  def change do
    create table(:newsletter_editions, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :title, :string, null: false
      add :subject, :string, null: false
      add :intro_text, :text, null: true

      add :cover_image_id,
          references(:images, column: :id, type: :binary_id, on_delete: :nilify_all), null: true

      add :post_ids, {:array, :string}, default: [], null: false
      add :event_ids, {:array, :string}, default: [], null: false
      add :status, :string, null: false, default: "draft"
      add :scheduled_at, :utc_datetime, null: true
      add :sent_at, :utc_datetime, null: true
      add :sent_count, :integer, null: false, default: 0

      timestamps()
    end

    create index(:newsletter_editions, [:cover_image_id])
    create index(:newsletter_editions, [:status])
    create index(:newsletter_editions, [:scheduled_at])
    create index(:newsletter_editions, [:sent_at])
  end
end
