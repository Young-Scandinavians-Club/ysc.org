defmodule YscWeb.Emails.TicketReservationCreated do
  @moduledoc """
  Email sent to a member when staff create a ticket reservation (hold) on their behalf.
  """
  use MjmlEEx,
    mjml_template: "templates/ticket_reservation_created.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      format_datetime: 1,
      format_event_start_datetime: 2,
      member_greeting_name: 1,
      plain_text_from_html: 1
    ]

  alias Ysc.Events.TicketReservation
  alias Ysc.Repo

  def get_template_name, do: "ticket_reservation_created"

  def get_subject(%{event_title: title})
      when is_binary(title) and title != "" do
    "[YSC] Tickets reserved for you: #{title}"
  end

  def get_subject(_), do: "[YSC] Tickets reserved for you"

  def event_url(event_id), do: absolute_url("/events/#{event_id}")

  def notification_settings_url, do: absolute_url("/users/notifications")

  @doc """
  Builds assigns for `render/1` from a reservation preloaded with
  `:user`, `:created_by`, and `ticket_tier: :event`.
  """
  def prepare_email_data(%TicketReservation{} = reservation) do
    reservation =
      Repo.preload(reservation, [:user, :created_by, ticket_tier: :event])

    if is_nil(reservation.user) do
      raise ArgumentError, "Ticket reservation missing user"
    end

    if is_nil(reservation.ticket_tier) do
      raise ArgumentError, "Ticket reservation missing ticket tier"
    end

    event = reservation.ticket_tier.event

    if is_nil(event) do
      raise ArgumentError,
            "Ticket tier missing event for reservation #{reservation.id}"
    end

    event_description = plain_text_from_html(event.description)

    %{
      first_name: member_greeting_name(reservation.user),
      event_title: event.title,
      event: %{
        title: event.title,
        description: event_description,
        location_name: event.location_name,
        address: event.address,
        age_restriction: event.age_restriction
      },
      event_date_time:
        format_event_start_datetime(event.start_date, event.start_time),
      event_url: event_url(event.id),
      ticket_tier_name: reservation.ticket_tier.name,
      quantity: reservation.quantity,
      discount_display: format_discount(reservation.discount_percentage),
      has_discount: discount_positive?(reservation.discount_percentage),
      hold_expires_display: format_hold_expires(reservation.expires_at),
      has_notes: notes_present?(reservation.notes),
      notes_text: format_notes(reservation.notes),
      reserved_by_display: format_reserved_by(reservation.created_by),
      notification_settings_url: notification_settings_url()
    }
  end

  defp format_discount(nil), do: "None"

  defp format_discount(%Decimal{} = d) do
    if Decimal.compare(d, Decimal.new(0)) == :eq do
      "None"
    else
      "#{Decimal.round(d, 2) |> Decimal.to_string(:normal)}% member pricing"
    end
  end

  defp format_discount(_), do: "None"

  defp discount_positive?(nil), do: false

  defp discount_positive?(%Decimal{} = d),
    do: Decimal.compare(d, Decimal.new(0)) == :gt

  defp discount_positive?(_), do: false

  defp format_hold_expires(nil),
    do:
      "No fixed end date — complete checkout on the event page when you are ready."

  defp format_hold_expires(%DateTime{} = dt) do
    "Complete checkout before #{format_datetime(dt)}"
  end

  defp notes_present?(notes) when is_binary(notes), do: String.trim(notes) != ""
  defp notes_present?(_), do: false

  defp format_notes(nil), do: nil

  defp format_notes(notes) when is_binary(notes) do
    case String.trim(notes) do
      "" ->
        nil

      trimmed ->
        plain_text_from_html(trimmed)
    end
  end

  defp format_notes(_), do: nil

  defp format_reserved_by(nil), do: "YSC staff"

  defp format_reserved_by(user) do
    parts = [user.first_name, user.last_name] |> Enum.reject(&blank?/1)

    case parts do
      [] -> "YSC staff"
      _ -> Enum.join(parts, " ")
    end
  end

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false
end
