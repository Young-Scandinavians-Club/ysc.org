defmodule Ysc.Merch.CartEvent do
  @moduledoc """
  One thing that happened to a line in a member's merch cart, kept so the shop
  dashboard can see history that `merch_cart_items` (the cart as it is now)
  cannot show.

  The log is a ledger of units, so for any line `added - removed - purchased`
  is what is in the cart:

    * `:added` - units the cart grew by (an add to cart, or raising the
      quantity on the cart page). Capped adds record only the units that
      really went in; an add that changed nothing records nothing.
    * `:removed` - units the cart shrank by (lowering the quantity, or
      taking the line out)
    * `:purchased` - units that were in the line when its order was fulfilled
  """
  use Ecto.Schema

  @actions [:added, :removed, :purchased]

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime_usec]

  schema "merch_cart_events" do
    field :action, Ecto.Enum, values: @actions
    field :quantity, :integer

    belongs_to :user, Ysc.Accounts.User
    belongs_to :variant, Ysc.Merch.Variant

    timestamps(updated_at: false)
  end
end
