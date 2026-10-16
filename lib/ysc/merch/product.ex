defmodule Ysc.Merch.Product do
  @moduledoc """
  A merch product mirrored from a Printful sync product.

  Name, image and variants are owned by Printful and overwritten on sync.
  `description`, `status` and `sort_order` are owned by the club and never
  touched by a sync.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "merch_products" do
    field :printful_product_id, :integer
    field :name, :string
    field :description, :string
    field :source_image_url, :string
    field :status, Ecto.Enum, values: [:active, :hidden], default: :active
    field :sort_order, :integer, default: 0
    field :synced_at, :utc_datetime
    field :removed_from_printful_at, :utc_datetime

    belongs_to :image, Ysc.Media.Image

    has_many :variants, Ysc.Merch.Variant, foreign_key: :product_id
    has_many :gallery_images, Ysc.Merch.ProductImage, foreign_key: :product_id

    timestamps()
  end

  @doc """
  Changeset for fields synced from Printful.
  """
  def sync_changeset(product, attrs) do
    product
    |> cast(attrs, [
      :printful_product_id,
      :name,
      :source_image_url,
      :image_id,
      :synced_at,
      :removed_from_printful_at
    ])
    |> validate_required([:printful_product_id, :name])
    |> validate_length(:name, max: 255)
    |> unique_constraint(:printful_product_id)
  end

  @doc """
  Changeset for the club-managed fields edited in the admin.
  """
  def admin_changeset(product, attrs) do
    product
    |> cast(attrs, [:description, :status, :sort_order])
    |> validate_length(:description, max: 5_000)
  end
end
