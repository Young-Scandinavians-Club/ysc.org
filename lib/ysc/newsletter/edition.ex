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
    field :recipient_count, :integer
    field :archived_html, :string

    belongs_to :cover_image, Image
    belongs_to :creator, User
    belongs_to :updated_by, User

    timestamps()
  end

  @draft_fields [
    :title,
    :subject,
    :intro_text,
    :cover_image_id,
    :post_ids,
    :event_ids
  ]

  @doc """
  Changeset for creating or updating an edition.
  """
  def changeset(edition, attrs) do
    edition
    |> cast(
      attrs,
      @draft_fields ++
        [:status, :scheduled_at, :sent_at, :sent_count, :recipient_count]
    )
    |> validate_required([:title, :subject])
    |> shared_validations()
  end

  @doc """
  Changeset for member-facing draft saves from the newsletter editor.

  Lifecycle fields (`status`, `scheduled_at`, `sent_at`, `sent_count`) must be
  updated only via `Newsletter.send_edition/1`, `schedule_edition/2`, etc.
  """
  def draft_changeset(edition, attrs) do
    edition
    |> cast(attrs, @draft_fields)
    |> validate_required([:title, :subject])
    |> shared_validations()
  end

  defp shared_validations(changeset) do
    changeset
    |> validate_length(:title, max: 255)
    |> validate_length(:subject, max: 255)
    |> validate_length(:intro_text, max: 50_000)
    |> foreign_key_constraint(:cover_image_id)
  end
end
