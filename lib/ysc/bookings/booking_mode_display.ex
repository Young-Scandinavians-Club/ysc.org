defmodule Ysc.Bookings.BookingModeDisplay do
  @moduledoc """
  Human-readable labels for booking modes (`:room`, `:day`, `:buyout`).

  Use `label/1` for emails and user-facing booking summaries.
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
  Returns true when the booking mode is a buyout (atom or string).
  """
  def buyout?(:buyout), do: true
  def buyout?("buyout"), do: true
  def buyout?(_), do: false
end
