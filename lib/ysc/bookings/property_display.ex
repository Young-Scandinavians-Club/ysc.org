defmodule Ysc.Bookings.PropertyDisplay do
  @moduledoc """
  Human-readable labels for booking properties (`:tahoe`, `:clear_lake`).

  Use `short_name/2` for emails and compact UI, `medium_name/2` for home-page
  cards, and `full_name/2` for booking details and receipts.
  """

  @doc """
  Short label for emails, SMS, and compact UI (e.g. `"Tahoe"`, `"Clear Lake"`).

  Unknown atoms are title-cased. Returns `default` for other values.
  """
  def short_name(property, default \\ "Cabin")

  def short_name(:tahoe, _default), do: "Tahoe"
  def short_name(:clear_lake, _default), do: "Clear Lake"
  def short_name("tahoe", default), do: short_name(:tahoe, default)
  def short_name("clear_lake", default), do: short_name(:clear_lake, default)
  def short_name(property, _default) when is_binary(property), do: property

  def short_name(property, _default) when is_atom(property),
    do: String.capitalize(to_string(property))

  def short_name(_, default), do: default

  @doc """
  Medium label without the cabin suffix (e.g. `"Lake Tahoe"`, `"Clear Lake"`).

  Returns `default` for unknown values.
  """
  def medium_name(property, default \\ "Unknown")

  def medium_name(:tahoe, _default), do: "Lake Tahoe"
  def medium_name(:clear_lake, _default), do: "Clear Lake"
  def medium_name("tahoe", default), do: medium_name(:tahoe, default)
  def medium_name("clear_lake", default), do: medium_name(:clear_lake, default)
  def medium_name(_, default), do: default

  @doc """
  Full cabin name for booking details and receipts
  (e.g. `"Lake Tahoe Cabin"`, `"Clear Lake Cabin"`).

  Returns `default` for unknown values.
  """
  def full_name(property, default \\ "Unknown")

  def full_name(:tahoe, _default), do: "Lake Tahoe Cabin"
  def full_name(:clear_lake, _default), do: "Clear Lake Cabin"
  def full_name("tahoe", default), do: full_name(:tahoe, default)
  def full_name("clear_lake", default), do: full_name(:clear_lake, default)
  def full_name(_, default), do: default

  @doc """
  Label for outage notifications (e.g. `"Tahoe Property"`, `"Clear Lake Property"`).

  Accepts atoms and known string keys. Returns `default` for unknown values.
  """
  def outage_name(property, default \\ "Property")

  def outage_name(:tahoe, _default), do: "Tahoe Property"
  def outage_name(:clear_lake, _default), do: "Clear Lake Property"
  def outage_name("tahoe", default), do: outage_name(:tahoe, default)
  def outage_name("clear_lake", default), do: outage_name(:clear_lake, default)
  def outage_name(_, default), do: default

  @doc """
  Physical address string for a booking property.

  Returns `default` for unknown values.
  """
  def address(property, default \\ "Property Address")

  def address(:tahoe, _default), do: "2685 Cedar Lane, Homewood, CA 96141"

  def address(:clear_lake, _default),
    do: "9325 Bass Road, Kelseyville, CA 95451"

  def address("tahoe", default), do: address(:tahoe, default)
  def address("clear_lake", default), do: address(:clear_lake, default)
  def address(_, default), do: default
end
