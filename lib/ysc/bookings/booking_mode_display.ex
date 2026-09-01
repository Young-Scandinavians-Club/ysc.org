defmodule Ysc.Bookings.BookingModeDisplay do
  @moduledoc """
  Human-readable labels for booking modes (`:room`, `:day`, `:buyout`).

  Use `label/1` for emails (`"Room Booking"`, `"Day Booking"`). Use
  `stay_type_label/1` for member booking UIs (`"Individual room(s)"`,
  `"Shared cabin"`). Buyout is `"Entire cabin"` in both.
  """

  @doc """
  Human-readable label (e.g. `"Room Booking"`, `"Day Booking"`, `"Entire cabin"`).

  Accepts atoms and known string keys. Unknown atoms are title-cased.
  """
  def label(:room), do: "Room Booking"
  def label(:day), do: "Day Booking"
  def label(:buyout), do: "Entire cabin"
  def label("room"), do: label(:room)
  def label("day"), do: label(:day)
  def label("buyout"), do: label(:buyout)

  def label(mode) when is_atom(mode), do: String.capitalize(to_string(mode))
  def label(mode) when is_binary(mode), do: mode

  @doc """
  Member-facing stay type used on receipts, booking details, and policy tables.

  Matches the booking UI (unlike `label/1`, which uses `"Room Booking"` /
  `"Day Booking"` in emails):

    * `:buyout` — `"Entire cabin"`
    * `:room` — `"Individual room(s)"`
    * `:day` — `"Shared cabin"`

  Accepts atoms and known string keys. Other values fall back to `"Shared cabin"`,
  matching the previous catch-all in booking receipts and details.

  ## Examples

      iex> stay_type_label(:buyout)
      "Entire cabin"

      iex> stay_type_label(:room)
      "Individual room(s)"

      iex> stay_type_label(:day)
      "Shared cabin"
  """
  def stay_type_label(:buyout), do: "Entire cabin"
  def stay_type_label(:room), do: "Individual room(s)"
  def stay_type_label(:day), do: "Shared cabin"
  def stay_type_label("buyout"), do: stay_type_label(:buyout)
  def stay_type_label("room"), do: stay_type_label(:room)
  def stay_type_label("day"), do: stay_type_label(:day)
  def stay_type_label(_), do: "Shared cabin"

  @doc """
  Returns true when the booking mode is a buyout (atom or string).
  """
  def buyout?(:buyout), do: true
  def buyout?("buyout"), do: true
  def buyout?(_), do: false
end
