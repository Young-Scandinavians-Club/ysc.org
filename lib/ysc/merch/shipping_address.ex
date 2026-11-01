defmodule Ysc.Merch.ShippingAddress do
  @moduledoc """
  A merch delivery address, validated for Printful. Not persisted on its own:
  checkout and the admin order form use it to validate input, then snapshot the
  fields onto the order.

  v1 ships to US addresses only.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA
             MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX
             UT VT VA WA WV WI WY PR)

  @primary_key false
  embedded_schema do
    field :name, :string
    field :address1, :string
    field :address2, :string
    field :city, :string
    field :state_code, :string
    field :zip, :string
    field :country_code, :string, default: "US"
    field :phone, :string
    field :email, :string
  end

  @type t :: %__MODULE__{}

  @fields [
    :name,
    :address1,
    :address2,
    :city,
    :state_code,
    :zip,
    :country_code,
    :phone,
    :email
  ]

  def states, do: @states

  def changeset(address \\ %__MODULE__{}, attrs) do
    address
    |> cast(attrs, @fields)
    |> update_change(:state_code, &normalize_state/1)
    |> update_change(:country_code, &(&1 |> String.trim() |> String.upcase()))
    |> validate_required([:name, :address1, :city, :state_code, :zip])
    |> validate_length(:name, max: 100)
    |> validate_length(:address1, max: 100)
    |> validate_length(:address2, max: 100)
    |> validate_length(:city, max: 60)
    |> validate_length(:phone, max: 30)
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:country_code, ["US"],
      message: "we can only ship within the United States for now"
    )
    |> validate_inclusion(:state_code, @states, message: "must be a US state")
    |> validate_format(:zip, ~r/^\d{5}(-\d{4})?$/,
      message: "must be a 5-digit ZIP code"
    )
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/,
      message: "must be a valid email"
    )
  end

  @doc """
  Validates `attrs` and returns `{:ok, %ShippingAddress{}}` or
  `{:error, changeset}`.
  """
  def validate(attrs) do
    attrs |> then(&changeset(%__MODULE__{}, &1)) |> apply_action(:validate)
  end

  @doc "The address as Printful's `recipient` object."
  def to_recipient(%__MODULE__{} = a) do
    %{
      name: a.name,
      address1: a.address1,
      address2: Ysc.Text.blank_to_nil(a.address2),
      city: a.city,
      state_code: a.state_code,
      country_code: a.country_code,
      zip: a.zip,
      phone: Ysc.Text.blank_to_nil(a.phone),
      email: Ysc.Text.blank_to_nil(a.email)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Maps to the order columns (`recipient_name`, `address1`, ...).
  """
  def to_order_attrs(%__MODULE__{} = a) do
    %{
      recipient_name: a.name,
      address1: a.address1,
      address2: Ysc.Text.blank_to_nil(a.address2),
      city: a.city,
      state_code: a.state_code,
      zip: a.zip,
      country_code: a.country_code,
      phone: Ysc.Text.blank_to_nil(a.phone),
      email: Ysc.Text.blank_to_nil(a.email)
    }
  end

  @doc """
  An address pre-filled with what we know about a member: name, phone, email,
  and their billing address when it is in the US. `user` needs
  `:billing_address` preloaded.
  """
  def from_user(user) do
    billing = user.billing_address

    base = %__MODULE__{
      name: String.trim("#{user.first_name} #{user.last_name}"),
      phone: user.phone_number,
      email: user.email
    }

    if billing && us_country?(billing.country) do
      %{
        base
        | address1: billing.address,
          city: billing.city,
          zip: billing.postal_code,
          state_code: state_code(billing.region)
      }
    else
      base
    end
  end

  defp us_country?(country) when is_binary(country) do
    String.upcase(String.trim(country)) in [
      "US",
      "USA",
      "UNITED STATES",
      "UNITED STATES OF AMERICA"
    ]
  end

  defp us_country?(_), do: false

  defp state_code(region) when is_binary(region) do
    code = region |> String.trim() |> String.upcase()
    if code in @states, do: code
  end

  defp state_code(_), do: nil

  @doc "Rebuilds an address from an order's snapshot columns."
  def from_order(order) do
    %__MODULE__{
      name: order.recipient_name,
      address1: order.address1,
      address2: order.address2,
      city: order.city,
      state_code: order.state_code,
      zip: order.zip,
      country_code: order.country_code,
      phone: order.phone,
      email: order.email
    }
  end

  @doc """
  Street lines for display: `address1`, optional `address2`, then
  `City, ST ZIP`. Blank lines are omitted.

  Accepts `%ShippingAddress{}`, `%Ysc.Merch.Order{}`, and any map with those
  keys. Used by shop/admin views and merch emails.

      display_lines(address)
      # => ["1 Market St", "San Francisco, CA 94105"]
  """
  def display_lines(%{
        address1: address1,
        address2: address2,
        city: city,
        state_code: state_code,
        zip: zip
      }) do
    [
      address1,
      address2,
      "#{city}, #{state_code} #{zip}"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp normalize_state(nil), do: nil
  defp normalize_state(state), do: state |> String.trim() |> String.upcase()
end
