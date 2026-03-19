defmodule Ysc.Repo.Migrations.CreateEmailEvents do
  use Ecto.Migration

  def change do
    create table(:email_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :event_type, :string, null: false
      add :email, :citext, null: false
      add :environment, :string, null: false
      add :template, :string, null: true

      add :edition_id,
          references(:newsletter_editions, column: :id, type: :binary_id, on_delete: :nilify_all),
          null: true

      add :subscriber_id,
          references(:newsletter_subscribers,
            column: :id,
            type: :binary_id,
            on_delete: :nilify_all
          ),
          null: true

      add :user_id,
          references(:users, column: :id, type: :binary_id, on_delete: :nilify_all),
          null: true

      add :bounce_type, :string, null: true
      add :bounce_sub_type, :string, null: true
      add :link_url, :text, null: true
      add :raw_payload, :jsonb, null: false, default: "{}"
      add :event_timestamp, :utc_datetime, null: true

      timestamps()
    end

    create index(:email_events, [:email])
    create index(:email_events, [:edition_id])
    create index(:email_events, [:event_type])
    create index(:email_events, [:subscriber_id])
    create index(:email_events, [:user_id])
    create index(:email_events, [:environment])
    create index(:email_events, [:template])
    create index(:email_events, [:inserted_at])
  end
end
