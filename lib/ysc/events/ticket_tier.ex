defmodule Ysc.Events.TicketTier do
  @moduledoc """
  Ticket tier schema and changesets.

  Defines the TicketTier database schema, validations, and changeset functions
  for ticket tier data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ticket_tiers" do
    field :name, :string
    field :description, :string

    field :type, Ysc.Events.TicketTierType

    field :price, Money.Ecto.Composite.Type, default_currency: :USD
    field :quantity, :integer
    field :unlimited_quantity, :boolean, virtual: true

    # If this is set all the tickets require to have
    # a registration attached to them
    field :requires_registration, :boolean

    # Set a start and end date for the ticket tier
    # when it goes on sale and when the sale ends
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime

    belongs_to :event, Ysc.Events.Event, foreign_key: :event_id, references: :id

    field :lock_version, :integer, default: 1

    timestamps()
  end

  @doc """
  Creates a changeset for the TicketTier schema.
  """
  def changeset(ticket_tier, attrs \\ %{}) do
    # Normalize empty strings to nil for date fields before casting
    normalized_attrs =
      attrs
      |> normalize_date_field(:start_date)
      |> normalize_date_field(:end_date)

    ticket_tier
    |> cast(normalized_attrs, [
      :name,
      :description,
      :type,
      :quantity,
      :unlimited_quantity,
      :price,
      :requires_registration,
      :start_date,
      :end_date,
      :event_id,
      :lock_version
    ])
    |> validate_required([
      :name,
      :type,
      :event_id
    ])
    |> enforce_free_price()
    |> validate_required_price()
    |> validate_quantity()
    |> validate_datetime_order()
    |> validate_money(:price)
    |> optimistic_lock(:lock_version)
    |> foreign_key_constraint(:event_id)
  end

  # Normalize empty strings and invalid date strings to nil for date fields
  defp normalize_date_field(attrs, field) when is_atom(field) do
    field_str = Atom.to_string(field)
    value = Map.get(attrs, field_str) || Map.get(attrs, field)

    case value do
      "" ->
        Map.put(attrs, field_str, nil)

      nil ->
        attrs

      value when is_binary(value) ->
        # Try to parse the date string, if it fails, set to nil
        case DateTime.from_iso8601(value) do
          {:ok, _datetime, _offset} -> attrs
          {:error, _} -> Map.put(attrs, field_str, nil)
        end

      _ ->
        attrs
    end
  end

  # Custom validation for price field - required for paid types only
  # Donation types allow nil price (user sets arbitrary amount)
  defp validate_required_price(changeset) do
    type = get_field(changeset, :type)
    price = get_field(changeset, :price)

    case {type, price} do
      {:free, _} -> changeset
      {"free", _} -> changeset
      {:donation, _} -> changeset
      {"donation", _} -> changeset
      {_, nil} -> add_error(changeset, :price, "is required for paid tickets")
      {_, ""} -> add_error(changeset, :price, "is required for paid tickets")
      _ -> changeset
    end
  end

  # Ensure FREE ticket tiers always have price set to 0 USD
  defp enforce_free_price(changeset) do
    case get_field(changeset, :type) do
      :free -> put_change(changeset, :price, Money.new(0, :USD))
      "free" -> put_change(changeset, :price, Money.new(0, :USD))
      _ -> changeset
    end
  end

  # Custom validation for quantity field - must be positive when present, nil means infinite
  # Convert 0 to nil to treat it as unlimited
  defp validate_quantity(changeset) do
    quantity = get_field(changeset, :quantity)

    case quantity do
      nil ->
        changeset

      0 ->
        put_change(changeset, :quantity, nil)

      quantity when is_integer(quantity) and quantity > 0 ->
        changeset

      quantity when is_integer(quantity) and quantity < 0 ->
        add_error(changeset, :quantity, "must be greater than or equal to 0")

      _ ->
        changeset
    end
  end

  # Custom validation for money field
  defp validate_money(changeset, field) do
    validate_change(changeset, field, fn _field, value ->
      case value do
        %Money{currency: :USD} = money when money.amount >= 0 ->
          []

        %Money{currency: currency} when currency != :USD ->
          [{field, "must be in USD"}]

        %Money{amount: amount} when amount < 0 ->
          [{field, "must be greater than or equal to 0"}]

        nil ->
          []

        _ ->
          [{field, "invalid money format"}]
      end
    end)
  end

  # Private function to validate that end_date is after start_date if both are present
  defp validate_datetime_order(changeset) do
    case {get_field(changeset, :start_date), get_field(changeset, :end_date)} do
      {start_date, end_date}
      when not is_nil(start_date) and not is_nil(end_date) ->
        if DateTime.compare(end_date, start_date) == :gt do
          changeset
        else
          add_error(changeset, :end_date, "must be after start date")
        end

      _ ->
        changeset
    end
  end
end
