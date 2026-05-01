defmodule Ysc.Bookings.BookingEntitlement do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "booking_entitlements" do
    field :benefit_kind, Ysc.Bookings.BookingEntitlementBenefitKind
    field :status, Ysc.Bookings.BookingEntitlementStatus, default: :active

    field :property, Ysc.Bookings.BookingProperty
    field :max_guests, :integer
    field :free_nights, :integer
    field :percent_off, :decimal
    field :amount_off, Money.Ecto.Composite.Type, default_currency: :USD

    field :buyout_max_discount, Money.Ecto.Composite.Type,
      default_currency: :USD

    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime
    field :internal_note, :string

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    belongs_to :issued_by_user, Ysc.Accounts.User,
      foreign_key: :issued_by_user_id,
      references: :id

    belongs_to :room, Ysc.Bookings.Room, foreign_key: :room_id, references: :id

    belongs_to :consumed_booking, Ysc.Bookings.Booking,
      foreign_key: :consumed_booking_id,
      references: :id

    timestamps()
  end

  @create_cast [
    :user_id,
    :issued_by_user_id,
    :benefit_kind,
    :status,
    :property,
    :room_id,
    :max_guests,
    :free_nights,
    :percent_off,
    :amount_off,
    :buyout_max_discount,
    :expires_at,
    :internal_note
  ]

  def create_changeset(struct, attrs) do
    struct
    |> cast(attrs, @create_cast)
    |> validate_required([:user_id, :benefit_kind])
    |> validate_number(:max_guests, greater_than: 0)
    |> validate_benefit_fields()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:issued_by_user_id)
    |> foreign_key_constraint(:room_id)
  end

  defp validate_benefit_fields(changeset) do
    kind = get_field(changeset, :benefit_kind)

    case kind do
      :free_nights ->
        changeset
        |> validate_required([:free_nights, :buyout_max_discount])
        |> validate_number(:free_nights, greater_than: 0)

      :percent_off ->
        changeset
        |> validate_required([:percent_off, :buyout_max_discount])
        |> validate_change(:percent_off, fn _, p ->
          cond do
            is_nil(p) ->
              []

            Decimal.compare(p, Decimal.new(0)) != :gt ->
              [{:percent_off, "must be greater than 0"}]

            Decimal.compare(p, Decimal.new(100)) == :gt ->
              [{:percent_off, "must be at most 100"}]

            true ->
              []
          end
        end)

      :fixed_amount_off ->
        validate_required(changeset, [:amount_off])

      _ ->
        changeset
    end
  end

  def revoke_changeset(%__MODULE__{} = ent) do
    change(ent, %{status: :revoked})
  end
end
