defmodule Ysc.Posts.Post do
  @moduledoc """
  Post schema and changesets.

  Defines the Post database schema, validations, and changeset functions
  for post data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :state,
      :user_id,
      :title
    ],
    sortable: [:inserted_at, :title, :state, :author_name],
    default_limit: 50,
    max_limit: 200,
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    },
    adapter_opts: [
      join_fields: [
        author_first: [
          binding: :author,
          field: :first_name,
          ecto_type: :string
        ],
        author_last: [
          binding: :author,
          field: :first_name,
          ecto_type: :string
        ]
      ],
      compound_fields: [
        author_name: [:author_first, :author_last]
      ]
    ]
  }

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "posts" do
    belongs_to :author, Ysc.Accounts.User,
      foreign_key: :user_id,
      references: :id

    belongs_to :updated_by, Ysc.Accounts.User,
      foreign_key: :updated_by_id,
      references: :id

    field :state, PostState
    field :title, :string

    field :url_name, :string
    field :rendered_body, :string
    field :raw_body, :string
    field :preview_text, :string

    belongs_to :featured_image, Ysc.Media.Image,
      foreign_key: :image_id,
      references: :id

    field :featured_post, :boolean

    field :published_on, :utc_datetime
    field :deleted_on, :utc_datetime

    # Snapshot of author's board position when the post was first published
    field :board_position_at_publish, :string

    # Easier to render with normalized value and no join required
    field :comment_count, :integer

    timestamps()
  end

  @editor_fields [
    :title,
    :url_name,
    :rendered_body,
    :raw_body,
    :image_id,
    :preview_text
  ]

  @doc """
  Changeset for admin editor auto-save and validate.

  Publishing state and featured-post flags must use dedicated actions
  (`publish-post`, `restore-post`, `delete-post`), not LiveView form params.
  """
  def editor_changeset(post, attrs, opts \\ []) do
    post
    |> cast(attrs, @editor_fields)
    |> validate_length(:title, max: 150)
    |> validate_length(:url_name, min: 1, max: 150)
    |> foreign_key_constraint(:image_id)
    |> maybe_validate_unique_url_name(opts)
  end

  def new_post_changeset(post, attrs, opts \\ []) do
    post
    |> cast(attrs, [
      :user_id,
      :state,
      :title,
      :url_name,
      :rendered_body,
      :raw_body,
      :preview_text,
      :image_id,
      :featured_post,
      :published_on,
      :deleted_on,
      :board_position_at_publish
    ])
    |> validate_length(:title, max: 150)
    |> validate_length(:url_name, min: 1, max: 150)
    |> foreign_key_constraint(:image_id)
    |> maybe_validate_unique_url_name(opts)
  end

  def update_post_changeset(post, attrs, opts \\ []) do
    post
    |> cast(attrs, [
      :state,
      :title,
      :url_name,
      :rendered_body,
      :raw_body,
      :image_id,
      :preview_text,
      :featured_post,
      :published_on,
      :deleted_on,
      :comment_count,
      :board_position_at_publish
    ])
    |> validate_length(:title, max: 150)
    |> validate_length(:url_name, min: 1, max: 150)
    |> foreign_key_constraint(:image_id)
    |> maybe_validate_unique_url_name(opts)
  end

  def update_comment_count_changeset(post, attrs, _opts \\ []) do
    post |> cast(attrs, [:comment_count])
  end

  defp maybe_validate_unique_url_name(changeset, opts) do
    if Keyword.get(opts, :validate_url_name, false) do
      changeset
      |> unsafe_validate_unique(:url_name, Ysc.Repo)
      |> unique_constraint(:url_name)
    else
      changeset
    end
  end
end
