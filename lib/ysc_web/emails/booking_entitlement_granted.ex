defmodule YscWeb.Emails.BookingEntitlementGranted do
  @moduledoc """
  Notifies a member that a cabin booking benefit was added to their account.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_entitlement_granted.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.MoneyHelper

  def get_template_name, do: "booking_entitlement_granted"

  def get_subject, do: "A cabin benefit for your next booking"

  def prepare_email_data(ent, user) do
    first_name = user.first_name || "there"
    base = YscWeb.Endpoint.url()

    {show_tahoe, show_clear, tahoe_url, clear_url} =
      case ent.property do
        nil ->
          {true, true, "#{base}/bookings/tahoe", "#{base}/bookings/clear-lake"}

        :tahoe ->
          {true, false, "#{base}/bookings/tahoe", nil}

        :clear_lake ->
          {false, true, nil, "#{base}/bookings/clear-lake"}
      end

    %{
      first_name: first_name,
      benefit_description: benefit_description(ent),
      property_line: property_line(ent),
      buyout_cap_line: buyout_cap_line(ent),
      expiry_line: expiry_line(ent),
      next_booking_notice: next_booking_notice(),
      show_tahoe_link: show_tahoe,
      show_clear_lake_link: show_clear,
      tahoe_book_url: tahoe_url,
      clear_lake_book_url: clear_url,
      manage_bookings_hint:
        "Start a new reservation to use this benefit — it appears on your price summary automatically before you confirm."
    }
  end

  def plain_text_summary(vars) do
    """
    Hi #{vars.first_name},

    #{vars.benefit_description}

    NEXT BOOKING ONLY:
    #{vars.next_booking_notice}

    #{vars.property_line}
    #{vars.buyout_cap_line}
    #{vars.expiry_line}

    #{if vars.show_tahoe_link, do: "Tahoe: #{vars.tahoe_book_url}\n", else: ""}#{if vars.show_clear_lake_link, do: "Clear Lake: #{vars.clear_lake_book_url}\n", else: ""}

    #{vars.manage_bookings_hint}
    """
    |> String.trim()
  end

  defp next_booking_notice do
    "This benefit is for your next eligible cabin booking. When you pick new dates and go through checkout, " <>
      "the discount is applied automatically to the total. It does not change past trips, completed stays, or bookings you already hold."
  end

  defp benefit_description(ent) do
    case ent.benefit_kind do
      :free_nights ->
        n = ent.free_nights || 0

        "#{n} free night#{if n == 1, do: "", else: "s"} on your next eligible stay (applied proportionally to the trip subtotal)."

      :percent_off ->
        "#{Decimal.round(ent.percent_off || Decimal.new(0), 2)}% off your next eligible cabin stay."

      :fixed_amount_off ->
        "A fixed discount of #{format_money(ent.amount_off)} on your next eligible cabin stay."
    end
  end

  defp property_line(ent) do
    case ent.property do
      nil -> "Property: any cabin (Tahoe or Clear Lake)."
      :tahoe -> "Property: Lake Tahoe cabin."
      :clear_lake -> "Property: Clear Lake cabin."
    end
  end

  defp buyout_cap_line(ent) do
    case ent.benefit_kind do
      :fixed_amount_off ->
        ""

      _ ->
        if ent.buyout_max_discount && Money.positive?(ent.buyout_max_discount) do
          "Full-property buyouts: savings are capped at #{format_money(ent.buyout_max_discount)} for this benefit."
        else
          ""
        end
    end
  end

  defp expiry_line(%{expires_at: nil}), do: "This benefit does not expire."

  defp expiry_line(%{expires_at: exp}) do
    "Expires: #{Calendar.strftime(exp, "%b %d, %Y %H:%M UTC")}."
  end

  defp format_money(nil), do: "$0.00"
  defp format_money(m), do: MoneyHelper.format_money!(m)
end
