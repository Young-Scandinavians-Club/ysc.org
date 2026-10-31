defmodule Ysc.Merch.CartEvent do
  @moduledoc """
  One thing that happened to a line in a member's merch cart, kept so the shop
  dashboard can see history that `merch_cart_items` (the cart as it is now)
  cannot show.

  `quantity` depends on the action:

    * `:added` - units added by this click
    * `:quantity_set` - the line's new quantity
    * `:removed` - units that were in the line when the member removed it
    * `:purchased` - units that were in the line when its order was fulfilled
  """
  use Ecto.Schema

  @actions [:added, :quantity_set, :removed, :purchased]

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "merch_cart_events" do
    field :action, Ecto.Enum, values: @actions
    field :quantity, :integer

    belongs_to :user, Ysc.Accounts.User
    belongs_to :variant, Ysc.Merch.Variant

    timestamps(updated_at: false)
  end

  @doc "All cart event actions."
  def actions, do: @actions
end
