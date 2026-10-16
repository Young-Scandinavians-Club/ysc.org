defmodule Ysc.Merch.ProductImage do
  @moduledoc """
  A photo in a product's gallery, optionally tied to one color.

  A photo with a `color` is shown only while that color is selected; a photo
  without one is shown for every color. `source` says who owns it: `:printful`
  photos come and go with catalog sync, `:admin` photos are the club's own.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "merch_product_images" do
    field :color, :string
    field :position, :integer, default: 0
    field :source, Ecto.Enum, values: [:printful, :admin], default: :admin
    field :source_image_url, :string

    belongs_to :product, Ysc.Merch.Product
    belongs_to :image, Ysc.Media.Image

    timestamps()
  end

  def changeset(product_image, attrs) do
    product_image
    |> cast(attrs, [
      :product_id,
      :image_id,
      :color,
      :position,
      :source,
      :source_image_url
    ])
    |> update_change(:color, &blank_to_nil/1)
    |> validate_required([:product_id, :image_id])
    |> validate_length(:color, max: 100)
    |> unique_constraint([:product_id, :image_id],
      name: :merch_product_images_product_id_image_id_index,
      message: "is already in this gallery"
    )
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:image_id)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
