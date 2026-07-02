defmodule Ysc.Email.LinkTrackingRoundTripTest do
  @moduledoc """
  Ensures `LinkTracking.disable_tracking/1` does not break rendered MJML email HTML.

  Floki round-trips can normalize attributes and whitespace; these tests render
  real templates and assert critical transactional content survives.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Email.LinkTracking
  alias YscWeb.Emails.{BookingCheckinReminder, ResetPassword}

  describe "disable_tracking/1 on rendered MJML templates" do
    test "ResetPassword preserves CTA href, btn_block class, and greeting" do
      reset_url = "https://ysc.org/users/reset-password?token=abc123"

      html =
        ResetPassword.render(%{
          first_name: "Alex",
          url: reset_url
        })

      tracked = LinkTracking.disable_tracking(html)

      assert anchor_hrefs(html) == anchor_hrefs(tracked)
      assert tracked =~ "Hello Alex!"
      assert tracked =~ "Reset Password"

      {:ok, document} = Floki.parse_fragment(tracked)

      cta = Floki.find(document, ".btn_block a[href=\"#{reset_url}\"]")
      assert length(cta) == 1
      assert Floki.attribute(cta, "ses:no-track") != []

      assert_all_anchors_have_no_track(document)
    end

    test "BookingCheckinReminder preserves door code, booking CTA, and contact links" do
      booking_url = "https://ysc.org/bookings/01HM1234567890ABCDEFGH/receipt"

      html =
        BookingCheckinReminder.render(%{
          first_name: "Alex",
          door_code: "4829",
          property: "tahoe",
          property_name: "Tahoe",
          property_address: "2685 Cedar Lane, Homewood, CA 96141",
          checkin_date: "December 1, 2024",
          checkout_date: "December 3, 2024",
          checkin_time: "3:00 PM",
          checkout_time: "11:00 AM",
          days_until_checkin: 2,
          booking_reference_id: "BK-123",
          booking_mode: "Room Booking",
          room_names: "Room 1",
          nights: 2,
          is_buyout: false,
          guests_count: 2,
          children_count: 0,
          cabin_master_name: "Jane Doe",
          cabin_master_email: "jane@example.com",
          cabin_master_phone: "415-555-1234",
          booking_url: booking_url
        })

      tracked = LinkTracking.disable_tracking(html)

      assert anchor_hrefs(html) == anchor_hrefs(tracked)
      assert tracked =~ ~s(<span class="door-code-value">4829</span>)
      assert tracked =~ "2685 Cedar Lane, Homewood, CA 96141"

      {:ok, document} = Floki.parse_fragment(tracked)

      booking_cta =
        Floki.find(document, ".btn_block a[href=\"#{booking_url}\"]")

      assert length(booking_cta) == 1
      assert Floki.attribute(booking_cta, "ses:no-track") != []

      assert Floki.find(document, ".door-code-value") |> Floki.text() == "4829"

      assert_all_anchors_have_no_track(document)
    end
  end

  defp anchor_hrefs(html) do
    {:ok, document} = Floki.parse_fragment(html)

    document
    |> Floki.find("a[href]")
    |> Floki.attribute("href")
    |> Enum.sort()
  end

  defp assert_all_anchors_have_no_track(document) do
    for anchor <- Floki.find(document, "a[href]") do
      assert Floki.attribute([anchor], "ses:no-track") != [],
             "expected ses:no-track on #{inspect(Floki.attribute([anchor], "href"))}"
    end
  end
end
