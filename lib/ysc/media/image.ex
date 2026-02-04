import EctoEnum

defenum(ImageProcessingState, [
  "unprocessed",
  "processing",
  "completed",
  "failed"
])

defmodule Ysc.Media.Image do
  @moduledoc """
  Image schema and changesets.

  Defines the Image database schema, validations, and changeset functions
  for image data manipulation.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:title, :alt_text, :user_id], sortable: [:inserted_at]
  }

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "images" do
    field :title, :string
    field :alt_text, :string

    field :raw_image_path, :string

    field :optimized_image_path, :string
    field :thumbnail_path, :string
    field :blur_hash, :string

    field :width, :integer
    field :height, :integer

    field :processing_state, ImageProcessingState

    belongs_to :uploader, Ysc.Accounts.User,
      foreign_key: :user_id,
      references: :id

    field :upload_data, :map

    timestamps()
  end

  def add_image_changeset(image, attrs, _opts \\ []) do
    image
    |> cast(attrs, [
      :title,
      :alt_text,
      :raw_image_path,
      :optimized_image_path,
      :thumbnail_path,
      :blur_hash,
      :width,
      :height,
      :processing_state,
      :user_id,
      :upload_data
    ])
    |> validate_length(:title, max: 255)
    |> validate_length(:alt_text, max: 512)
    |> validate_length(:raw_image_path, max: 2048)
    |> validate_required([:raw_image_path, :user_id])
  end

  def processed_image_changeset(image, attrs) do
    image
    |> cast(attrs, [
      :optimized_image_path,
      :thumbnail_path,
      :blur_hash,
      :width,
      :height,
      :processing_state
    ])
  end

  def edit_image_changeset(image, attrs) do
    image
    |> cast(attrs, [
      :title,
      :alt_text
    ])
  end

  def image_processing_state_changeset(image, state) do
    change(image, processing_state: state)
  end
end
