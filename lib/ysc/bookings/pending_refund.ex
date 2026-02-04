defmodule Ysc.Bookings.PendingRefund do
  @moduledoc """
  Schema for pending refunds that require admin review.

  When a booking is cancelled with a partial refund (less than 100%),
  a pending refund is created instead of automatically processing the refund.
  Admins can then review and approve the refund, potentially adjusting the amount.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User
  alias Ysc.Bookings.Booking
  alias Ysc.Ledgers.Payment

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "pending_refunds" do
    belongs_to :booking, Booking
    belongs_to :payment, Payment
    field :policy_refund_amount, Money.Ecto.Composite.Type
    field :admin_refund_amount, Money.Ecto.Composite.Type

    field :status, Ecto.Enum,
      values: [:pending, :approved, :rejected],
      default: :pending

    field :cancellation_reason, :string
    field :admin_notes, :string
    belongs_to :reviewed_by, User
    field :reviewed_at, :utc_datetime
    field :applied_rule_days_before_checkin, :integer
    field :applied_rule_refund_percentage, :decimal

    timestamps()
  end

  @doc false
  def changeset(pending_refund, attrs) do
    pending_refund
    |> cast(attrs, [
      :booking_id,
      :payment_id,
      :policy_refund_amount,
      :admin_refund_amount,
      :status,
      :cancellation_reason,
      :admin_notes,
      :reviewed_by_id,
      :reviewed_at,
      :applied_rule_days_before_checkin,
      :applied_rule_refund_percentage
    ])
    |> validate_required([
      :booking_id,
      :payment_id,
      :policy_refund_amount,
      :status
    ])
    |> validate_inclusion(:status, [:pending, :approved, :rejected])
  end
end
