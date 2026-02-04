defmodule Ysc.Subscriptions.SubscriptionItem do
  @moduledoc """
  Subscription item schema and changesets.

  Defines the SubscriptionItem database schema, validations, and changeset functions
  for subscription item data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "subscription_items" do
    field :stripe_id, :string
    field :stripe_product_id, :string
    field :stripe_price_id, :string
    field :quantity, :integer

    belongs_to :subscription, Ysc.Subscriptions.Subscription,
      foreign_key: :subscription_id,
      references: :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(subscription_item, attrs) do
    subscription_item
    |> cast(attrs, [
      :stripe_id,
      :stripe_product_id,
      :stripe_price_id,
      :quantity,
      :subscription_id
    ])
    |> validate_required([
      :stripe_id,
      :stripe_product_id,
      :stripe_price_id,
      :quantity,
      :subscription_id
    ])
    |> unique_constraint(:stripe_id)
  end
end
