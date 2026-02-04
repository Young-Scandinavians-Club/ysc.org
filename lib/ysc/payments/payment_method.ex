defmodule Ysc.Payments.PaymentMethod do
  @moduledoc """
  Payment method schema and changesets.

  Defines the PaymentMethod database schema, validations, and changeset functions
  for payment method data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "payment_methods" do
    field :provider, PaymentMethodProvider
    field :provider_id, :string
    field :provider_customer_id, :string

    field :type, PaymentMethodType
    field :provider_type, :string

    # General field
    field :last_four, :string
    field :display_brand, :string

    # Card specific
    field :exp_month, :integer
    field :exp_year, :integer

    # Bank account specific
    field :account_type, :string
    field :routing_number, :string
    field :bank_name, :string

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    field :is_default, :boolean, default: false

    field :payload, :map, default: %{}

    timestamps()
  end

  @doc false
  def changeset(payment_method, attrs) do
    payment_method
    |> cast(attrs, [
      :provider,
      :provider_id,
      :provider_customer_id,
      :type,
      :provider_type,
      :last_four,
      :display_brand,
      :exp_month,
      :exp_year,
      :account_type,
      :routing_number,
      :bank_name,
      :user_id,
      :is_default,
      :payload
    ])
    |> validate_required([
      :provider,
      :provider_id,
      :provider_customer_id,
      :type,
      :provider_type,
      :user_id
    ])
    |> validate_length(:provider_id, max: 255)
    |> validate_length(:provider_customer_id, max: 255)
    |> validate_length(:provider_type, max: 255)
    |> validate_length(:last_four, max: 4)
    |> validate_length(:display_brand, max: 255)
    |> validate_length(:account_type, max: 255)
    |> validate_length(:routing_number, max: 255)
    |> validate_length(:bank_name, max: 255)
    |> validate_inclusion(:exp_month, 1..12,
      message: "must be between 1 and 12"
    )
    |> validate_number(:exp_year,
      greater_than: 2000,
      message: "must be greater than 2000"
    )
    |> unique_constraint([:provider, :provider_id])
    |> foreign_key_constraint(:user_id)
  end
end
