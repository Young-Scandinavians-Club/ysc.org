defmodule YscWeb.BookingDisplay do
  @moduledoc """
  Human-readable booking and payment status labels for member-facing views.
  """

  @doc """
  Badge `type` for booking status on member booking detail pages.
  """
  def status_badge_type(:complete), do: "green"
  def status_badge_type(:hold), do: "yellow"
  def status_badge_type(:canceled), do: "red"
  def status_badge_type(:refunded), do: "red"
  def status_badge_type(_), do: "gray"

  @doc """
  Member-friendly label for a booking status atom.
  """
  def status_label(:hold), do: "Awaiting payment"
  def status_label(:complete), do: "Confirmed"
  def status_label(:canceled), do: "Cancelled"
  def status_label(:refunded), do: "Refunded"

  def status_label(status),
    do: status |> to_string() |> String.capitalize()

  @doc """
  Badge `type` for ledger payment status on member booking detail pages.
  """
  def payment_status_badge_type(:completed), do: "green"
  def payment_status_badge_type(:pending), do: "yellow"
  def payment_status_badge_type(:refunded), do: "red"
  def payment_status_badge_type(_), do: "gray"

  @doc """
  Member-friendly label for a ledger payment status atom.
  """
  def payment_status_label(:completed), do: "Completed"
  def payment_status_label(:pending), do: "Pending"
  def payment_status_label(:refunded), do: "Refunded"

  def payment_status_label(status),
    do: status |> to_string() |> String.capitalize()
end
