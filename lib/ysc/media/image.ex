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

  @default_blur_hash "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

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

    field :content_hash, :string

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
      :upload_data,
      :content_hash
    ])
    |> validate_length(:title, max: 255)
    |> validate_length(:alt_text, max: 512)
    |> validate_length(:raw_image_path, max: 2048)
    |> validate_required([:raw_image_path, :user_id])
    |> unique_constraint(:content_hash, name: :images_content_hash_index)
  end

  def processed_image_changeset(image, attrs) do
    image
    |> cast(attrs, [
      :optimized_image_path,
      :thumbnail_path,
      :blur_hash,
      :width,
      :height,
      :processing_state,
      :content_hash
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

  @doc """
  Returns the best path for displaying an image: optimized when present, otherwise raw.

  Returns `nil` when the image is `nil`.
  """
  def display_path(nil), do: nil

  def display_path(%__MODULE__{} = image) do
    image.optimized_image_path || image.raw_image_path
  end

  def display_path(%{raw_image_path: _} = image) do
    Map.get(image, :optimized_image_path) || Map.get(image, :raw_image_path)
  end

  @doc """
  Returns the default blur hash used when an image has no blur hash yet.

  Used for BlurHash canvas placeholders during progressive image loading.
  """
  def default_blur_hash, do: @default_blur_hash

  @doc """
  Returns a blur hash string suitable for BlurHash canvas placeholders.

  Uses the image's `blur_hash` when present; otherwise returns `default_blur_hash/0`.
  Accepts `nil` and non-image values (returns the default).
  """
  def blur_hash_for_display(nil), do: @default_blur_hash

  def blur_hash_for_display(%__MODULE__{blur_hash: blur_hash}) when is_binary(blur_hash),
    do: blur_hash

  def blur_hash_for_display(%__MODULE__{}), do: @default_blur_hash
  def blur_hash_for_display(_), do: @default_blur_hash
end
