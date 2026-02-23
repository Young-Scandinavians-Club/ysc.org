defmodule Ysc.Repo.Migrations.AddBoardPositionAtPublishToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :board_position_at_publish, :string
    end

    # Backfill from author's current board_position for existing published posts
    execute """
    UPDATE posts
    SET board_position_at_publish = users.board_position
    FROM users
    WHERE posts.user_id = users.id
      AND posts.state = 'published'
    """
  end
end
