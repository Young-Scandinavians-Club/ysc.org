defmodule Ysc.Merch.Order do
  @moduledoc """
  A merch order: either a member purchase (`:purchase`) or a club-paid order
  placed by an admin (`:admin_comp`), optionally linked to an event.

  `printful_cost` is what Printful charges the club. Until Printful reports the
  real figure, `estimated_cost` (quoted when the order was placed) stands in;
  see `cost/1`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.ReferenceGenerator

  @reference_prefix "MRC"

  @statuses [
    :pending,
    :paid,
    :submitting,
    :submitted,
    :in_production,
    :shipped,
    :delivered,
    :failed,
    :canceled,
    :refunded
  ]

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "merch_orders" do
    field :reference_id, :string
    field :kind, Ecto.Enum, values: [:purchase, :admin_comp]
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :purpose, :string

    field :recipient_name, :string
    field :address1, :string
    field :address2, :string
    field :city, :string
    field :state_code, :string
    field :zip, :string
    field :country_code, :string, default: "US"
    field :phone, :string
    field :email, :string

    field :subtotal, Money.Ecto.Composite.Type, default_currency: :USD
    field :shipping_amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :total_amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :shipping_method, :string

    field :payment_intent_id, :string

    field :printful_order_id, :integer
    field :estimated_cost, Money.Ecto.Composite.Type, default_currency: :USD
    field :printful_cost, Money.Ecto.Composite.Type, default_currency: :USD

    field :submitted_at, :utc_datetime
    field :printful_synced_at, :utc_datetime
    field :canceled_at, :utc_datetime
    field :failure_reason, :string

    belongs_to :user, Ysc.Accounts.User
    belongs_to :granted_by, Ysc.Accounts.User
    belongs_to :event, Ysc.Events.Event
    belongs_to :payment, Ysc.Ledgers.Payment

    has_many :items, Ysc.Merch.OrderItem, foreign_key: :order_id
    has_many :shipments, Ysc.Merch.Shipment, foreign_key: :order_id

    timestamps()
  end

  @doc "All order statuses."
  def statuses, do: @statuses

  @doc """
  Statuses in which Printful has accepted (and so will bill the club for) the
  order. Pending, failed, canceled and refunded orders cost the club nothing.
  """
  def billed_statuses,
    do: [:submitting, :submitted, :in_production, :shipped, :delivered]

  @doc """
  What this order costs the club: Printful's actual charge when known, else
  the estimate, else zero.
  """
  def cost(%__MODULE__{printful_cost: %Money{} = cost}), do: cost
  def cost(%__MODULE__{estimated_cost: %Money{} = cost}), do: cost
  def cost(%__MODULE__{}), do: Money.new(0, :USD)

  @doc "True when `cost/1` is still the pre-order estimate."
  def cost_estimated?(%__MODULE__{
        printful_cost: nil,
        estimated_cost: %Money{}
      }),
      do: true

  def cost_estimated?(%__MODULE__{}), do: false

  @doc """
  Changeset for a member purchase, created `:pending` at the payment step.
  Amounts are computed server-side from the catalog and Printful's quote;
  nothing monetary is cast from user input.
  """
  def purchase_changeset(order, attrs, user_id) do
    order
    |> cast(attrs, [
      :recipient_name,
      :address1,
      :address2,
      :city,
      :state_code,
      :zip,
      :country_code,
      :phone,
      :email,
      :shipping_method,
      :subtotal,
      :shipping_amount,
      :total_amount
    ])
    |> put_change(:user_id, user_id)
    |> put_change(:kind, :purchase)
    |> put_change(:status, :pending)
    |> validate_required([
      :user_id,
      :recipient_name,
      :address1,
      :city,
      :zip,
      :country_code,
      :shipping_method,
      :subtotal,
      :shipping_amount,
      :total_amount
    ])
    |> validate_non_negative(:total_amount)
    |> ReferenceGenerator.put_reference_id(@reference_prefix)
    |> unique_constraint(:reference_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for a club-paid order placed by an admin. The member is charged
  nothing; `estimated_cost` is Printful's quote at placement time.
  """
  def admin_comp_changeset(order, attrs, granted_by_id) do
    zero = Money.new(0, :USD)

    order
    |> cast(attrs, [
      :user_id,
      :event_id,
      :purpose,
      :recipient_name,
      :address1,
      :address2,
      :city,
      :state_code,
      :zip,
      :country_code,
      :phone,
      :email,
      :shipping_method,
      :estimated_cost
    ])
    |> put_change(:granted_by_id, granted_by_id)
    |> put_change(:kind, :admin_comp)
    |> put_change(:status, :submitting)
    |> put_change(:subtotal, zero)
    |> put_change(:shipping_amount, zero)
    |> put_change(:total_amount, zero)
    |> validate_required([
      :granted_by_id,
      :purpose,
      :recipient_name,
      :address1,
      :city,
      :zip,
      :country_code
    ])
    |> validate_length(:purpose, max: 500)
    |> validate_non_negative(:estimated_cost)
    |> ReferenceGenerator.put_reference_id(@reference_prefix)
    |> unique_constraint(:reference_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:granted_by_id)
  end

  @doc """
  Puts a new reference_id on the changeset (retry after a unique collision).
  """
  def put_new_reference_id(changeset) do
    ReferenceGenerator.put_new_reference_id(changeset, @reference_prefix)
  end

  defp validate_non_negative(changeset, field) do
    validate_change(changeset, field, fn _, money ->
      if Money.negative?(money),
        do: [{field, "must not be negative"}],
        else: []
    end)
  end
end
