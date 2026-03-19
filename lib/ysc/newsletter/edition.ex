defmodule Ysc.Newsletter.Edition do
  @moduledoc """
  Schema for a newsletter edition (curated content: cover, intro, posts, events).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Media.Image
  alias Ysc.Accounts.User

  @derive {
    Flop.Schema,
    filterable: [:status, :title, :creator_id],
    sortable: [:inserted_at, :sent_at, :title, :subject, :status],
    default_limit: 20,
    max_limit: 100,
    default_order: %{order_by: [:inserted_at], order_directions: [:desc]}
  }

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "newsletter_editions" do
    field :title, :string
    field :subject, :string
    field :intro_text, :string
    field :post_ids, {:array, :string}, default: []
    field :event_ids, {:array, :string}, default: []
    field :status, Ecto.Enum, values: [:draft, :scheduled, :sending, :sent]
    field :scheduled_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :sent_count, :integer, default: 0
    field :archived_html, :string

    belongs_to :cover_image, Image
    belongs_to :creator, User

    timestamps()
  end

  @doc """
  Changeset for creating or updating an edition.
  """
  def changeset(edition, attrs) do
    edition
    |> cast(attrs, [
      :title,
      :subject,
      :intro_text,
      :cover_image_id,
      :post_ids,
      :event_ids,
      :status,
      :scheduled_at,
      :sent_at,
      :sent_count
    ])
    |> validate_required([:title, :subject])
    |> validate_length(:title, max: 255)
    |> validate_length(:subject, max: 255)
    |> validate_length(:intro_text, max: 50_000)
    |> foreign_key_constraint(:cover_image_id)
  end
end
