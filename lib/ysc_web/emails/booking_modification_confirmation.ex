defmodule YscWeb.Emails.BookingModificationConfirmation do
  @moduledoc """
  Email template sent when a member modifies an existing booking.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_modification_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      booking_receipt_url: 1,
      booking_room_names: 1,
      ensure_booking: 2,
      format_money: 1
    ]

  alias YscWeb.Emails.BookingHelpers

  def get_template_name, do: "booking_modification_confirmation"

  def get_subject, do: "Your booking has been updated"

  def booking_url(booking_id), do: booking_receipt_url(booking_id)

  @doc """
  Prepares booking modification confirmation email data.
  """
  def prepare_email_data(booking, previous_details) do
    booking = ensure_booking(booking, [:user, :rooms])
    previous = BookingHelpers.normalize_previous_details(previous_details)

    booking
    |> BookingHelpers.member_links()
    |> Map.merge(BookingHelpers.stay_changes(booking, previous))
    |> Map.merge(%{
      booking:
        booking
        |> BookingHelpers.booking_summary()
        |> Map.merge(%{
          room_names: booking_room_names(booking),
          nights: Date.diff(booking.checkout_date, booking.checkin_date),
          total_amount: format_money(booking.total_price)
        }),
      previous:
        previous
        |> BookingHelpers.previous_stay_summary()
        |> Map.put(:total_amount, format_money(previous.total_price)),
      additional_payment: additional_payment_str(previous.additional_payment)
    })
  end

  defp additional_payment_str(%Money{} = money) do
    if Money.positive?(money), do: format_money(money), else: nil
  end

  defp additional_payment_str(_), do: nil
end
