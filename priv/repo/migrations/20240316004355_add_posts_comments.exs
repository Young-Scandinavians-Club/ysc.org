defmodule Ysc.Repo.Migrations.AddPostsComments do
  use Ecto.Migration

  def change do
    create table(:posts, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      # Who posted it
      add :user_id, references(:users, column: :id, type: :binary_id), null: false

      # Default here has to be a valid atom: [:draft, :published, :deleted]
      add :state, :string, null: false, default: "draft"
      add :title, :text, default: "Untitled Post"

      add :url_name, :text
      add :rendered_body, :text
      add :raw_body, :text
      add :preview_text, :text

      # Featured image
      add :image_id, references(:images, column: :id, type: :binary_id)
      add :featured_post, :boolean, default: false

      add :published_on, :utc_datetime
      add :deleted_on, :utc_datetime

      # Track number of comments for easy rendering of summary
      add :comment_count, :integer, default: 0

      timestamps()
    end

    create unique_index(:posts, [:url_name])
    create constraint(:posts, :comment_count_always_positive, check: "comment_count >= 0")
    create index(:posts, [:image_id])
    create index(:posts, [:user_id])

    create table(:post_events, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id, references(:users, column: :id, type: :binary_id), null: false
      add :post_id, references(:posts, column: :id, type: :binary_id), null: false

      add :event_type, :string, null: false

      add :from, :text
      add :to, :text

      timestamps()
    end

    create index(:post_events, [:post_id])
    create index(:post_events, [:user_id])

    create table(:comments, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :user_id, references(:users, column: :id, type: :binary_id), null: false
      add :post_id, references(:posts, column: :id, type: :binary_id), null: false

      # If is a reply
      add :comment_id, references(:comments, column: :id, type: :binary_id), null: true

      add :text, :text

      timestamps()
    end

    create index(:comments, [:post_id])
    create index(:comments, [:user_id])
    create index(:comments, [:comment_id])
  end
end
