defmodule Ysc.Tickets.TicketOrder do
  @moduledoc """
  Ticket order schema and changesets.

  Defines the TicketOrder database schema, validations, and changeset functions
  for ticket order data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.ReferenceGenerator

  @reference_prefix "ORD"

  @derive {
    Flop.Schema,
    filterable: [:user_id, :status, :event_id],
    sortable: [
      :reference_id,
      :status,
      :total_amount,
      :inserted_at,
      :completed_at
    ],
    default_limit: 50,
    max_limit: 200,
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "ticket_orders" do
    field :reference_id, :string
    field :status, Ysc.Events.TicketOrderStatus
    field :total_amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :discount_amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :payment_intent_id, :string
    field :expires_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :cancelled_at, :utc_datetime
    field :cancellation_reason, :string

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id
    belongs_to :event, Ysc.Events.Event, foreign_key: :event_id, references: :id

    belongs_to :payment, Ysc.Ledgers.Payment,
      foreign_key: :payment_id,
      references: :id

    has_many :tickets, Ysc.Events.Ticket,
      foreign_key: :ticket_order_id,
      references: :id

    timestamps()
  end

  @doc """
  Creates a changeset for ticket order creation.
  """
  def create_changeset(ticket_order, attrs) do
    ticket_order
    |> cast(attrs, [
      :user_id,
      :event_id,
      :total_amount,
      :discount_amount,
      :payment_intent_id,
      :expires_at
    ])
    |> validate_required([
      :user_id,
      :event_id,
      :total_amount,
      :expires_at
    ])
    |> validate_money(:total_amount)
    |> put_reference_id()
    |> unique_constraint(:reference_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:event_id)
  end

  @doc """
  Creates a changeset for updating ticket order status.
  """
  def status_changeset(ticket_order, attrs) do
    ticket_order
    |> cast(attrs, [
      :status,
      :payment_id,
      :completed_at,
      :cancelled_at,
      :cancellation_reason
    ])
    |> validate_inclusion(:status, [:pending, :completed, :cancelled, :expired])
    |> validate_money(:total_amount)
  end

  @doc """
  Creates a changeset for updating payment intent.
  """
  def payment_changeset(ticket_order, attrs) do
    ticket_order
    |> cast(attrs, [:payment_intent_id])
    |> validate_required([:payment_intent_id])
  end

  defp put_reference_id(changeset) do
    case get_field(changeset, :reference_id) do
      nil ->
        put_change(
          changeset,
          :reference_id,
          ReferenceGenerator.generate_reference_id(@reference_prefix)
        )

      _ ->
        changeset
    end
  end

  defp validate_money(changeset, field) do
    case get_field(changeset, field) do
      %Money{} = money ->
        if Money.positive?(money) or Money.zero?(money) do
          changeset
        else
          add_error(changeset, field, "must be greater than or equal to zero")
        end

      _ ->
        changeset
    end
  end
end
