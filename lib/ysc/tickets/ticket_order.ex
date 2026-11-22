defmodule Ysc.Tickets.TicketOrder do
  @moduledoc """
  Ticket order schema and changesets.

  Defines the TicketOrder database schema, validations, and changeset functions
  for ticket order data manipulation.
  """
  use Ecto.Schema
  use Flop.Schema
  import Ecto.Changeset

  alias Ysc.ReferenceGenerator

  @reference_prefix "ORD"

  @flop_options [
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
  ]

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
    field :admin_grant_notes, :string
    # Set only for in-person cash/check sales recorded via the admin app.
    # `payment_channel` is "cash" | "check" | "other"; the order `total_amount`
    # stays $0 (a grant), and `offline_amount_collected` is what the volunteer
    # physically took, for treasurer reconciliation.
    field :payment_channel, :string

    field :offline_amount_collected, Money.Ecto.Composite.Type,
      default_currency: :USD

    # Guest checkout (public-sale tiers): no account, so the buyer is identified
    # by these instead of `user_id`. See `guest?/1` and `buyer_email/1`.
    field :guest_email, :string
    field :guest_first_name, :string
    field :guest_last_name, :string

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id
    belongs_to :event, Ysc.Events.Event, foreign_key: :event_id, references: :id

    belongs_to :granted_by, Ysc.Accounts.User,
      foreign_key: :granted_by_id,
      references: :id

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
    |> put_change(:status, :pending)
    |> ReferenceGenerator.put_reference_id(@reference_prefix)
    |> unique_constraint(:reference_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:event_id)
  end

  @doc """
  Creates a changeset for a guest order: no account, identified by name and
  email. The email is normalized (trimmed, lowercased) so per-buyer checks and
  receipts agree on it.
  """
  def guest_create_changeset(ticket_order, attrs) do
    ticket_order
    |> cast(attrs, [
      :guest_email,
      :guest_first_name,
      :guest_last_name,
      :event_id,
      :total_amount,
      :discount_amount,
      :payment_intent_id,
      :expires_at
    ])
    |> update_change(:guest_email, &normalize_email/1)
    |> update_change(:guest_first_name, &String.trim/1)
    |> update_change(:guest_last_name, &String.trim/1)
    |> validate_required([
      :guest_email,
      :guest_first_name,
      :guest_last_name,
      :event_id,
      :total_amount,
      :expires_at
    ])
    |> validate_format(:guest_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:guest_email, max: 160)
    |> validate_length(:guest_first_name, max: 80)
    |> validate_length(:guest_last_name, max: 80)
    |> validate_money(:total_amount)
    |> put_change(:status, :pending)
    |> ReferenceGenerator.put_reference_id(@reference_prefix)
    |> unique_constraint(:reference_id)
    |> foreign_key_constraint(:event_id)
    |> check_constraint(:guest_email, name: :ticket_orders_buyer_present)
  end

  @doc "Trims and downcases an email address."
  def normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  def normalize_email(email), do: email

  @doc "True when the order was placed without an account."
  def guest?(%__MODULE__{user_id: nil, guest_email: email})
      when is_binary(email),
      do: true

  def guest?(_), do: false

  @doc """
  The buyer's email: the account email for members, the guest email otherwise.

  Needs `:user` preloaded for member orders. Returns nil when unknown.
  """
  def buyer_email(%__MODULE__{guest_email: email, user_id: nil}), do: email

  def buyer_email(%__MODULE__{user: %{email: email}}), do: email
  def buyer_email(_), do: nil

  @doc """
  A map shaped like a user, for admin cards and exports: the account for
  member orders, the guest's name and email for guest orders.

  Returns nil when neither is available.
  """
  def display_user(%__MODULE__{user_id: nil, guest_email: email} = order)
      when is_binary(email) do
    %{
      id: "guest",
      first_name: order.guest_first_name,
      last_name: order.guest_last_name,
      email: email,
      phone_number: nil
    }
  end

  def display_user(%__MODULE__{user: %Ecto.Association.NotLoaded{}}), do: nil
  def display_user(%__MODULE__{user: %{} = user}), do: user
  def display_user(_), do: nil

  @doc "The buyer's full name (guest name, or the account's name)."
  def buyer_name(%__MODULE__{user_id: nil} = order) do
    [order.guest_first_name, order.guest_last_name]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def buyer_name(%__MODULE__{user: %{first_name: first, last_name: last}}) do
    [first, last] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")
  end

  def buyer_name(_), do: ""

  @doc """
  Creates a changeset for an admin-granted complimentary ticket order.
  """
  def admin_grant_changeset(ticket_order, attrs, granted_by_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    ticket_order
    |> cast(attrs, [
      :user_id,
      :event_id,
      :total_amount,
      :discount_amount,
      :expires_at,
      :completed_at,
      :admin_grant_notes,
      :payment_channel,
      :offline_amount_collected
    ])
    |> put_change(:granted_by_id, granted_by_id)
    |> validate_required([
      :user_id,
      :event_id,
      :total_amount,
      :expires_at,
      :granted_by_id
    ])
    |> validate_money(:total_amount)
    |> put_change(:status, :completed)
    |> put_change(:completed_at, Map.get(attrs, :completed_at, now))
    |> ReferenceGenerator.put_reference_id(@reference_prefix)
    |> unique_constraint(:reference_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:granted_by_id)
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

  @doc """
  Puts a new reference_id on the changeset (for retry after unique constraint).
  Call this when insert fails with a reference_id unique constraint.
  """
  def put_new_reference_id(changeset) do
    ReferenceGenerator.put_new_reference_id(changeset, @reference_prefix)
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
