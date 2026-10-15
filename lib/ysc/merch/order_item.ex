defmodule Ysc.Merch.OrderItem do
  @moduledoc """
  A line on a merch order. Name and unit price are snapshots taken when the
  order was placed.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "merch_order_items" do
    field :quantity, :integer
    field :name, :string
    field :unit_price, Money.Ecto.Composite.Type, default_currency: :USD

    belongs_to :order, Ysc.Merch.Order
    belongs_to :variant, Ysc.Merch.Variant

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:variant_id, :quantity, :name, :unit_price])
    |> validate_required([:variant_id, :quantity, :name, :unit_price])
    |> validate_number(:quantity, greater_than: 0, less_than_or_equal_to: 500)
    |> foreign_key_constraint(:variant_id)
  end
end
