defmodule Ysc.Posts.Comment do
  @moduledoc """
  Comment schema and changesets.

  Defines the Comment database schema, validations, and changeset functions
  for comment data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "comments" do
    belongs_to :author, Ysc.Accounts.User,
      foreign_key: :user_id,
      references: :id

    belongs_to :post, Ysc.Posts.Post, foreign_key: :post_id, references: :id

    belongs_to :reply_to_comment, Ysc.Posts.Comment,
      foreign_key: :comment_id,
      references: :id

    field :text, :string

    timestamps()
  end

  def new_comment_changeset(comment, attrs, _opts \\ []) do
    comment
    |> cast(attrs, [
      :user_id,
      :post_id,
      :comment_id,
      :text
    ])
    |> validate_required([:user_id, :post_id, :text])
    |> validate_length(:text, min: 1, max: 2000)
  end
end
