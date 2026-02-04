defmodule Ysc.Bookings.RefundPolicy do
  @moduledoc """
  Refund policy schema and changesets.

  Represents a refund policy for a specific property and booking mode.
  Each policy can have multiple rules that define refund percentages
  based on days before check-in.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Bookings.{RefundPolicyRule, BookingProperty, BookingMode}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "refund_policies" do
    field :name, :string
    field :description, :string
    field :property, BookingProperty
    field :booking_mode, BookingMode
    field :is_active, :boolean, default: true

    has_many :rules, RefundPolicyRule,
      foreign_key: :refund_policy_id,
      on_delete: :delete_all

    timestamps()
  end

  @doc """
  Creates a changeset for the RefundPolicy schema.
  """
  def changeset(refund_policy, attrs \\ %{}) do
    refund_policy
    |> cast(attrs, [:name, :description, :property, :booking_mode, :is_active])
    |> validate_required([:name, :property, :booking_mode])
    |> validate_length(:name, max: 255)
    |> validate_length(:description, max: 5000)
    |> unique_constraint([:property, :booking_mode],
      name: :refund_policies_property_mode_active_unique,
      message:
        "An active policy already exists for this property and booking mode"
    )
  end
end
