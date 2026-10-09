defmodule YscWeb.Emails.BookingModificationCabinMasterNotification do
  @moduledoc """
  Email template for booking modification notification to Cabin Master.

  Sends an internal notification email to the Cabin Master when a booking at
  their property has its dates or guest counts changed.
  """
  use MjmlEEx,
    mjml_template:
      "templates/booking_modification_cabin_master_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      admin_booking_url: 1,
      ensure_booking: 1
    ]

  alias YscWeb.Emails.BookingHelpers

  def get_template_name(), do: "booking_modification_cabin_master_notification"

  def get_subject(), do: "Booking Modification Notification"

  @doc """
  Prepares booking modification cabin master notification email data.

  ## Parameters:
  - `booking`: The modified booking with preloaded associations
  - `previous_details`: Map of the booking's prior `:checkin_date`,
    `:checkout_date`, `:guests_count`, `:children_count`

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(booking, previous_details) do
    booking = ensure_booking(booking)
    previous = BookingHelpers.normalize_previous_details(previous_details)

    %{
      booking: BookingHelpers.booking_summary(booking),
      previous: BookingHelpers.previous_stay_summary(previous),
      user: BookingHelpers.staff_user_summary(booking.user),
      booking_url: admin_booking_url(booking.id)
    }
    |> Map.merge(BookingHelpers.stay_changes(booking, previous))
  end
end
