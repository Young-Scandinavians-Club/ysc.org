defmodule Ysc.Repo.Migrations.CreateBoardPositions do
  use Ecto.Migration

  def change do
    create table(:board_positions, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :user_id, references(:users, column: :id, type: :binary_id), null: false
      add :position, :string, null: false
      add :started_on, :date, null: false
      add :ended_on, :date

      timestamps()
    end

    create index(:board_positions, [:user_id])
    create index(:board_positions, [:ended_on])

    # Backfill: one open record per user who currently has a board position
    execute """
            INSERT INTO board_positions (id, user_id, position, started_on, ended_on, inserted_at, updated_at)
            SELECT
              gen_random_uuid(),
              id,
              board_position,
              CURRENT_DATE,
              NULL,
              NOW(),
              NOW()
            FROM users
            WHERE board_position IS NOT NULL
            """,
            ""
  end
end
