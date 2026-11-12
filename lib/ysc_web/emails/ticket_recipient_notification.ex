defmodule YscWeb.Emails.TicketRecipientNotification do
  @moduledoc """
  Email sent to a person someone else bought (or was granted) a ticket for.

  When a ticket's attendee details carry an email address that differs from the
  purchaser's, that person gets their own ticket here: who it's from, the event,
  and the QR code and wallet buttons, none of which need a sign-in. The
  purchaser keeps receiving the full confirmation covering every ticket.
  """
  # Imported before `use MjmlEEx`, which compiles the template at that point.
  import YscWeb.Emails.TicketAccessHelpers,
    only: [apple_wallet_badge_url: 0, google_wallet_badge_url: 0]

  use MjmlEEx,
    mjml_template: "templates/ticket_recipient_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      attendee_greeting_name: 1,
      event_url: 1,
      format_event_start_datetime: 3
    ]

  alias YscWeb.Emails.TicketAccessHelpers

  def get_template_name() do
    "ticket_recipient_notification"
  end

  def get_subject() do
    "Your ticket is ready! 🎫"
  end

  def get_subject(event_title) when is_binary(event_title) do
    ticket_subject(event_title, 1)
  end

  def get_subject(%{event: %{title: title}, ticket_count: count})
      when is_binary(title) and is_integer(count) do
    ticket_subject(title, count)
  end

  def get_subject(_email_data), do: get_subject()

  defp ticket_subject(title, 1), do: "Your ticket to #{title} 🎫"
  defp ticket_subject(title, _count), do: "Your tickets to #{title} 🎫"

  @doc """
  The people besides the purchaser who should get their own email for this
  order. See `TicketAccessHelpers.guest_groups/1`.
  """
  def recipients(ticket_order),
    do: TicketAccessHelpers.guest_groups(ticket_order)

  @doc """
  Prepares the email data for one recipient group from `recipients/1`.

  `ticket_order` needs `user`, `event` and `tickets` (with tier and
  registration) loaded, as `Ysc.Tickets.get_ticket_order_for_email/1` returns.
  """
  def prepare_email_data(ticket_order, %{tickets: tickets} = recipient) do
    event = ticket_order.event

    %{
      first_name: attendee_greeting_name(recipient),
      purchaser_name: purchaser_name(ticket_order.user),
      ticket_count: length(tickets),
      event: %{
        title: event.title,
        location_name: event.location_name,
        address: event.address,
        age_restriction: event.age_restriction
      },
      event_date_time:
        format_event_start_datetime(event.start_date, event.start_time, "TBD"),
      event_url: event_url(event.id),
      ticket_cards: TicketAccessHelpers.ticket_cards(tickets)
    }
  end

  # Full name for the "from" line; falls back to a neutral phrase so the email
  # never reads "Valued Member bought you a ticket".
  defp purchaser_name(user) do
    [user.first_name, user.last_name]
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.map(&String.trim/1)
    |> case do
      [] -> "Someone"
      parts -> Enum.join(parts, " ")
    end
  end
end
