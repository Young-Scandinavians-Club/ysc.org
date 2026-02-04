defmodule Ysc.Repo.Migrations.AddEventTables do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :reference_id, :string

      add :state, :string, default: "draft"
      add :published_at, :utc_datetime, null: true
      add :publish_at, :utc_datetime, null: true

      add :organizer_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing)

      add :title, :text
      add :description, :text, null: true
      add :max_attendees, :integer, null: true
      add :age_restriction, :integer, null: true
      add :show_participants, :boolean, default: false

      add :raw_details, :text, null: true
      add :rendered_details, :text, null: true

      add :image_id, references(:images, column: :id, type: :binary_id, on_delete: :nothing),
        null: true

      add :start_date, :utc_datetime, null: true
      add :start_time, :time, null: true
      add :end_date, :utc_datetime, null: true
      add :end_time, :time, null: true

      add :location_name, :text, null: true
      add :address, :text, null: true
      add :latitude, :float, null: true
      add :longitude, :float, null: true
      add :place_id, :text, null: true

      add :lock_version, :integer, default: 1

      timestamps()
    end

    create unique_index(:events, [:reference_id])
    create index(:events, [:state])
    create index(:events, [:image_id])

    create table(:agendas, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :event_id, references(:events, column: :id, type: :binary_id, on_delete: :delete_all)
      add :title, :text
      add :position, :integer, default: 0

      timestamps()
    end

    create index(:agendas, [:event_id])

    create table(:agenda_items, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :agenda_id, references(:agendas, column: :id, type: :binary_id, on_delete: :delete_all)

      add :position, :integer, default: 0

      add :title, :text
      add :description, :text, null: true
      add :start_time, :time, null: true
      add :end_time, :time, null: true

      timestamps()
    end

    create index(:agenda_items, [:agenda_id])

    create table(:faq_questions, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :event_id, references(:events, column: :id, type: :binary_id, on_delete: :delete_all)

      add :question, :text
      add :answer, :text

      timestamps()
    end

    create index(:faq_questions, [:event_id])

    create table(:ticket_tiers, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :name, :text
      add :description, :text, null: true

      add :type, :string, default: "paid"

      add :price, :money_with_currency
      add :quantity, :integer, null: true

      add :requires_registration, :boolean, default: false

      add :start_date, :utc_datetime, null: true
      add :end_date, :utc_datetime, null: true

      add :event_id, references(:events, column: :id, type: :binary_id, on_delete: :nothing)

      add :lock_version, :integer, default: 1

      timestamps()
    end

    create index(:ticket_tiers, [:event_id])

    create table(:tickets, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :reference_id, :string

      add :event_id, references(:events, column: :id, type: :binary_id, on_delete: :nothing)

      add :ticket_tier_id,
          references(:ticket_tiers, column: :id, type: :binary_id, on_delete: :nothing)

      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing)

      add :status, :string, default: "pending"

      add :payment_id, references(:payments, column: :id, type: :binary_id, on_delete: :nothing),
        null: true

      add :expires_at, :utc_datetime

      timestamps()
    end

    create unique_index(:tickets, [:reference_id])
    create index(:tickets, [:event_id])
    create index(:tickets, [:status])
    create index(:tickets, [:payment_id])
    create index(:tickets, [:user_id])
    create index(:tickets, [:ticket_tier_id])

    create table(:ticket_details, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :ticket_id, references(:tickets, column: :id, type: :binary_id)

      add :first_name, :text
      add :last_name, :text
      add :email, :text

      timestamps()
    end

    create index(:ticket_details, [:ticket_id])
  end
end
