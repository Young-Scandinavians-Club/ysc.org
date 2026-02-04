defmodule Ysc.Accounts.Address do
  @moduledoc """
  Address schema and changesets.

  Defines the Address database schema, validations, and changeset functions
  for user billing address data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "addresses" do
    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    field :address, :string
    field :city, :string
    field :region, :string
    field :postal_code, :string
    field :country, :string

    timestamps()
  end

  @doc """
  A changeset for creating or updating an address.
  """
  def changeset(address, attrs) do
    address
    |> cast(attrs, [:address, :city, :region, :postal_code, :country, :user_id])
    |> validate_required([:address, :city, :postal_code, :country])
    |> validate_length(:address, max: 255)
    |> validate_length(:city, max: 100)
    |> validate_length(:region, max: 100)
    |> validate_length(:postal_code, max: 20)
    |> validate_length(:country, max: 100)
  end

  @doc """
  Creates an address changeset from signup application data.
  """
  def from_signup_application_changeset(address, signup_application) do
    changeset(address, %{
      address: signup_application.address,
      city: signup_application.city,
      region: signup_application.region,
      postal_code: signup_application.postal_code,
      country: signup_application.country
    })
  end
end
