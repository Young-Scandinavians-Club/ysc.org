defmodule Ysc.Repo.Migrations.AddMessageIdempotency do
  use Ecto.Migration

  def change do
    create table(:message_idempotency_entries, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :message_type, :string, null: false, default: "email"
      add :idempotency_key, :text, null: false
      add :message_template, :text, null: false
      add :params, :map, null: false, default: %{}

      add :rendered_message, :text, null: true

      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing),
        null: true

      add :email, :citext, null: true
      add :phone_number, :text, null: true

      timestamps()
    end

    create unique_index(
             :message_idempotency_entries,
             [:message_type, :idempotency_key, :message_template],
             name: :message_idempotency_entries_unique_index
           )

    create index(:message_idempotency_entries, [:email])
    create index(:message_idempotency_entries, [:phone_number])
    create index(:message_idempotency_entries, [:user_id])
  end
end
