defmodule Ysc.Repo.Migrations.CreateNewsletterSubscribers do
  use Ecto.Migration

  def change do
    create table(:newsletter_subscribers, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :email, :citext, null: false
      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nilify_all)
      add :first_name, :text
      add :last_name, :text
      add :subscribed, :boolean, null: false, default: true
      add :subscription_token, :string, null: false
      add :source, :text, null: true
      add :metadata, :jsonb, default: "{}"
      add :subscribed_at, :utc_datetime, null: false
      add :unsubscribed_at, :utc_datetime, null: true

      timestamps()
    end

    create unique_index(:newsletter_subscribers, [:email])
    create unique_index(:newsletter_subscribers, [:subscription_token])
    create index(:newsletter_subscribers, [:user_id])
    create index(:newsletter_subscribers, [:subscribed, :email])
    create index(:newsletter_subscribers, [:source, :subscribed_at])

    create constraint(:newsletter_subscribers, :subscribed_at_set_when_subscribed,
             check: "NOT subscribed OR (subscribed_at IS NOT NULL)"
           )
  end
end
