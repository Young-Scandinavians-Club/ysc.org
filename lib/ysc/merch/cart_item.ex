defmodule Ysc.Merch.CartItem do
  @moduledoc """
  A line in a member's merch cart. One row per variant; quantity is capped so
  a runaway client can't build an absurd order.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @max_quantity 25

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "merch_cart_items" do
    field :quantity, :integer

    belongs_to :user, Ysc.Accounts.User
    belongs_to :variant, Ysc.Merch.Variant

    timestamps()
  end

  def max_quantity, do: @max_quantity

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:quantity])
    |> validate_required([:quantity])
    |> validate_number(:quantity,
      greater_than: 0,
      less_than_or_equal_to: @max_quantity
    )
    |> unique_constraint([:user_id, :variant_id],
      name: :merch_cart_items_user_id_variant_id_index
    )
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:variant_id)
  end
end
