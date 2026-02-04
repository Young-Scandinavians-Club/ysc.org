defmodule Ysc.Repo.Migrations.AddContactForm do
  use Ecto.Migration

  def change do
    create table(:contact_forms, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :name, :text, null: false
      add :email, :citext, null: false
      add :subject, :text, null: false
      add :message, :text, null: false

      add :user_id, references(:users, on_delete: :nilify_all, column: :id, type: :binary_id),
        null: true

      timestamps()
    end

    create index(:contact_forms, [:user_id])
    create index(:contact_forms, [:email])
  end
end
