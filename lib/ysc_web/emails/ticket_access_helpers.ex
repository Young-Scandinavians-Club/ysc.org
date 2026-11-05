defmodule YscWeb.Emails.TicketAccessHelpers do
  @moduledoc """
  Sign-in-free ticket access for ticket emails.

  Ticket emails are read by people who may never have logged in (volunteers
  who were granted a ticket, guests a member bought a ticket for), so every
  link in them is a signed `Ysc.Tickets.AccessToken` URL rather than a page
  behind login:

    * `/t/:token` - the ticket page with QR codes and wallet buttons
    * `/t/:token/qr.png` - the QR code as an image the email embeds
    * `/t/:token/apple` and `/t/:token/google` - add one ticket to a wallet

  `ticket_cards/1` builds the per-ticket maps both ticket emails render, and
  `guest_groups/1` works out which other people the order's tickets were
  bought for.
  """

  import YscWeb.Emails.Helpers, only: [absolute_url: 1]

  alias Ysc.AppleWallet
  alias Ysc.Events.TicketTierHelpers
  alias Ysc.GoogleWallet
  alias Ysc.Tickets.AccessToken

  @doc """
  Public link to every ticket in the order.
  """
  def order_tickets_url(order_id),
    do: absolute_url("/t/" <> AccessToken.sign_order(order_id))

  @doc """
  Public link to the given tickets only.
  """
  def tickets_url(ticket_ids),
    do: absolute_url("/t/" <> AccessToken.sign_tickets(ticket_ids))

  @doc """
  Maps the tickets that can be used at the door to the per-ticket email data:
  holder, QR image and wallet links.

  Donations and unconfirmed tickets are left out. Wallet links are `nil` when
  that wallet isn't configured, so the template can skip the button.
  """
  def ticket_cards(tickets) when is_list(tickets) do
    apple? = AppleWallet.configured?(:ticket)
    google? = GoogleWallet.configured?(:ticket)

    tickets
    |> Enum.filter(&TicketTierHelpers.check_in_ticket?/1)
    |> Enum.map(fn ticket ->
      token = AccessToken.sign_ticket(ticket.id)

      %{
        reference_id: ticket.reference_id,
        ticket_tier_name: ticket.ticket_tier.name,
        holder_name: holder_name(ticket),
        qr_image_url: absolute_url("/t/#{token}/qr.png"),
        ticket_url: absolute_url("/t/#{token}"),
        apple_wallet_url: apple? && absolute_url("/t/#{token}/apple"),
        google_wallet_url: google? && absolute_url("/t/#{token}/google")
      }
    end)
  end

  @doc """
  Groups the order's check-in tickets by the email address given for the
  attendee, leaving out the purchaser (their email already lists every ticket).

  Returns `[%{email: email, first_name: name_or_nil, tickets: [ticket]}]`.
  """
  def guest_groups(%{user: user, tickets: tickets}) do
    purchaser_email = normalize_email(user.email)

    tickets
    |> Enum.filter(&TicketTierHelpers.check_in_ticket?/1)
    |> Enum.flat_map(fn ticket ->
      case ticket_email(ticket) do
        nil -> []
        email -> [{email, ticket}]
      end
    end)
    |> Enum.reject(fn {email, _ticket} -> email == purchaser_email end)
    |> Enum.group_by(fn {email, _ticket} -> email end, fn {_email, ticket} ->
      ticket
    end)
    |> Enum.sort_by(fn {email, _tickets} -> email end)
    |> Enum.map(fn {email, group} ->
      %{email: email, first_name: first_name(List.first(group)), tickets: group}
    end)
  end

  @doc """
  Lowercased, trimmed email, or `nil` when blank.
  """
  def normalize_email(email) when is_binary(email) do
    case email |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_email(_), do: nil

  defp ticket_email(%{registration: %{email: email}}),
    do: normalize_email(email)

  defp ticket_email(_), do: nil

  defp first_name(%{registration: %{first_name: first}}) when is_binary(first),
    do: String.trim(first)

  defp first_name(_), do: nil

  defp holder_name(%{registration: %{first_name: first, last_name: last}})
       when is_binary(first) and first != "" do
    [first, last]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(" ")
  end

  defp holder_name(_), do: nil
end
