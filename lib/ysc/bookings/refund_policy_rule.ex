defmodule Ysc.Bookings.RefundPolicyRule do
  @moduledoc """
  Refund policy rule schema and changesets.

  Represents a single rule within a refund policy that defines
  the refund percentage based on days before check-in.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Ysc.Bookings.RefundPolicy

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "refund_policy_rules" do
    field :days_before_checkin, :integer
    field :refund_percentage, :decimal
    field :description, :string
    field :priority, :integer, default: 0

    belongs_to :refund_policy, RefundPolicy,
      foreign_key: :refund_policy_id,
      references: :id

    timestamps()
  end

  @doc """
  Creates a changeset for the RefundPolicyRule schema.
  """
  def changeset(refund_policy_rule, attrs \\ %{}) do
    refund_policy_rule
    |> cast(attrs, [
      :days_before_checkin,
      :refund_percentage,
      :description,
      :priority,
      :refund_policy_id
    ])
    |> validate_required([
      :days_before_checkin,
      :refund_percentage,
      :refund_policy_id
    ])
    |> validate_number(:days_before_checkin, greater_than_or_equal_to: 0)
    |> validate_number(:refund_percentage,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_length(:description, max: 500)
    |> foreign_key_constraint(:refund_policy_id)
  end

  @doc """
  Query helper to order rules by days_before_checkin descending, then by priority ascending.
  This ensures the most restrictive rule (fewest days) is evaluated first.
  """
  def ordered_by_days(query) do
    from r in query,
      order_by: [desc: r.days_before_checkin, asc: r.priority]
  end
end
