defmodule Ysc.Merch.Variant do
  @moduledoc """
  A purchasable merch variant (size/color) mirrored from a Printful sync
  variant. `retail_price` is the Printful retail price and is what members pay.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "merch_variants" do
    field :printful_sync_variant_id, :integer
    field :printful_variant_id, :integer
    field :name, :string
    field :size, :string
    field :color, :string
    field :sku, :string
    field :retail_price, Money.Ecto.Composite.Type, default_currency: :USD
    field :source_image_url, :string
    field :available, :boolean, default: true

    belongs_to :product, Ysc.Merch.Product
    belongs_to :image, Ysc.Media.Image

    timestamps()
  end

  @doc """
  Changeset for fields synced from Printful.
  """
  def sync_changeset(variant, attrs) do
    variant
    |> cast(attrs, [
      :product_id,
      :printful_sync_variant_id,
      :printful_variant_id,
      :name,
      :size,
      :color,
      :sku,
      :retail_price,
      :source_image_url,
      :image_id,
      :available
    ])
    |> validate_required([
      :product_id,
      :printful_sync_variant_id,
      :printful_variant_id,
      :name,
      :retail_price
    ])
    |> validate_retail_price()
    |> unique_constraint(:printful_sync_variant_id)
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:image_id)
  end

  defp validate_retail_price(changeset) do
    validate_change(changeset, :retail_price, fn :retail_price, price ->
      cond do
        price.currency != :USD -> [retail_price: "must be in USD"]
        Money.negative?(price) -> [retail_price: "must not be negative"]
        true -> []
      end
    end)
  end
end
