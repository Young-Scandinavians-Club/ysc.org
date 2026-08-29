defmodule YscWeb.Emails.BookingEntitlementGranted do
  @moduledoc """
  Notifies a member that a cabin booking benefit was added to their account.
  """
  use MjmlEEx,
    mjml_template: "templates/booking_entitlement_granted.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers,
    only: [
      absolute_url: 1,
      attendee_greeting_name: 1,
      format_datetime: 1,
      format_money: 1,
      tahoe_booking_url: 0
    ]

  def get_template_name, do: "booking_entitlement_granted"

  def get_subject, do: "A cabin benefit for your next booking"

  def prepare_email_data(ent, user) do
    first_name = attendee_greeting_name(user)

    {show_tahoe, show_clear, tahoe_url, clear_url} =
      case ent.property do
        nil ->
          {true, true, tahoe_booking_url(),
           absolute_url("/bookings/clear-lake")}

        :tahoe ->
          {true, false, tahoe_booking_url(), nil}

        :clear_lake ->
          {false, true, nil, absolute_url("/bookings/clear-lake")}
      end

    {header_image_url, header_image_alt} = header_image(ent.property)

    %{
      first_name: first_name,
      header_image_url: header_image_url,
      header_image_alt: header_image_alt,
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
        "Start a new booking to use this benefit — it appears on your price summary automatically before you confirm."
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

  defp header_image(:tahoe) do
    {absolute_url("/images/tahoe-cabin-feature.jpg"), "Lake Tahoe cabin"}
  end

  defp header_image(:clear_lake) do
    {absolute_url("/images/clear_lake/clear_lake_cabin.webp"),
     "Clear Lake cabin"}
  end

  defp header_image(nil) do
    {absolute_url("/images/clear_lake/clear_lake_main.webp"),
     "YSC cabin getaway — book Lake Tahoe or Clear Lake"}
  end

  defp next_booking_notice do
    "This benefit is for your next eligible cabin booking. When you pick new dates and go through checkout, " <>
      "the discount is applied automatically to the total. It does not change past trips, completed stays, or bookings you've already made."
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
      nil -> "Cabin: Tahoe or Clear Lake."
      :tahoe -> "Cabin: Lake Tahoe."
      :clear_lake -> "Cabin: Clear Lake."
    end
  end

  defp buyout_cap_line(ent) do
    case ent.benefit_kind do
      :fixed_amount_off ->
        ""

      _ ->
        if ent.buyout_max_discount && Money.positive?(ent.buyout_max_discount) do
          "If you book the entire cabin, savings on that stay are capped at #{format_money(ent.buyout_max_discount)}."
        else
          ""
        end
    end
  end

  defp expiry_line(%{expires_at: nil}), do: "This benefit does not expire."

  defp expiry_line(%{expires_at: exp}) do
    "Use by #{format_datetime(exp)}."
  end
end
