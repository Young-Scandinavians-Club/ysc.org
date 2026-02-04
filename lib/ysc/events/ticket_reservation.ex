defmodule Ysc.Events.TicketReservation do
  @moduledoc """
  Ticket reservation schema and changesets.

  Defines the TicketReservation database schema, validations, and changeset functions
  for ticket reservation data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User
  alias Ysc.Tickets.TicketOrder

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "ticket_reservations" do
    belongs_to :ticket_tier, Ysc.Events.TicketTier,
      foreign_key: :ticket_tier_id,
      references: :id

    belongs_to :user, User, foreign_key: :user_id, references: :id
    belongs_to :created_by, User, foreign_key: :created_by_id, references: :id

    belongs_to :ticket_order, TicketOrder,
      foreign_key: :ticket_order_id,
      references: :id

    field :quantity, :integer
    field :discount_percentage, :decimal
    field :expires_at, :utc_datetime
    field :notes, :string
    field :status, :string, default: "active"
    field :fulfilled_at, :utc_datetime
    field :cancelled_at, :utc_datetime

    timestamps()
  end

  @doc """
  Creates a changeset for the TicketReservation schema.
  """
  def changeset(ticket_reservation, attrs \\ %{}) do
    ticket_reservation
    |> cast(attrs, [
      :ticket_tier_id,
      :user_id,
      :quantity,
      :discount_percentage,
      :expires_at,
      :notes,
      :created_by_id,
      :status,
      :fulfilled_at,
      :cancelled_at,
      :ticket_order_id
    ])
    |> validate_required([:ticket_tier_id, :user_id, :quantity, :created_by_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:discount_percentage,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_status()
    |> validate_expires_at()
    |> foreign_key_constraint(:ticket_tier_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:ticket_order_id)
  end

  defp validate_status(changeset) do
    status = get_field(changeset, :status)

    if status in ["active", "fulfilled", "cancelled"] do
      changeset
    else
      add_error(
        changeset,
        :status,
        "must be one of: active, fulfilled, cancelled"
      )
    end
  end

  defp validate_expires_at(changeset) do
    expires_at = get_field(changeset, :expires_at)

    case expires_at do
      nil ->
        changeset

      expires_at when is_struct(expires_at, DateTime) ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          changeset
        else
          add_error(changeset, :expires_at, "must be in the future")
        end

      _ ->
        changeset
    end
  end
end
