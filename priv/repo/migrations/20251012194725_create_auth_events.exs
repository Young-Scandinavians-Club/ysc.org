defmodule Ysc.Repo.Migrations.CreateAuthEvents do
  use Ecto.Migration

  def change do
    create table(:auth_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      # User reference (nullable for failed login attempts with non-existent users)
      add :user_id, references(:users, column: :id, type: :binary_id, on_delete: :nothing),
        null: true

      # Authentication attempt details
      # "login_attempt", "login_success", "login_failure", "logout", "password_reset", etc.
      add :event_type, :text, null: false
      add :success, :boolean, null: false
      # "invalid_credentials", "account_locked", "email_not_confirmed", etc.
      add :failure_reason, :text, null: true

      # User identification (for failed attempts where user_id might be null)
      add :email_attempted, :text, null: true

      # Network and device information
      add :ip_address, :text, null: true
      add :user_agent, :text, null: true
      # "desktop", "mobile", "tablet"
      add :device_type, :text, null: true
      add :browser, :text, null: true
      add :browser_version, :text, null: true
      add :operating_system, :text, null: true
      add :os_version, :text, null: true

      # Geographic information (if available)
      add :country, :text, null: true
      add :region, :text, null: true
      add :city, :text, null: true
      add :latitude, :float, null: true
      add :longitude, :float, null: true

      # Security and risk assessment
      add :is_suspicious, :boolean, default: false
      # 0-100 scale
      add :risk_score, :integer, null: true
      # ["unusual_location", "new_device", "rapid_attempts"]
      add :threat_indicators, {:array, :string}, default: []

      # Session information
      add :session_id, :text, null: true
      add :remember_me, :boolean, default: false

      # Additional metadata
      # For storing additional context-specific data
      add :metadata, :map, default: %{}

      timestamps()
    end

    # Indexes for efficient querying
    create index(:auth_events, [:user_id])
    create index(:auth_events, [:event_type])

    # Composite indexes for common queries
    create index(:auth_events, [:user_id, :inserted_at])
    create index(:auth_events, [:ip_address, :inserted_at])
    create index(:auth_events, [:event_type, :success, :inserted_at])
  end
end
