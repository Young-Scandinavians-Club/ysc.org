defmodule YscWeb.Emails.TahoeKitchenFundTest do
  @moduledoc """
  The Tahoe confirmation, check-in and check-out emails link to the Tahoe
  kitchen fund post; Clear Lake emails do not.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures

  alias Ysc.Repo

  alias YscWeb.Emails.{
    BookingCheckinReminder,
    BookingCheckoutReminder,
    BookingConfirmation
  }

  @fund_url "https://ysc.org/posts/tahoe-winter-20262027-season-open-for-bookings"

  for mod <- [
        BookingConfirmation,
        BookingCheckinReminder,
        BookingCheckoutReminder
      ] do
    describe "#{inspect(mod)}" do
      test "links to the kitchen fund for Tahoe bookings" do
        html = render_for(unquote(mod), :tahoe)
        assert html =~ @fund_url
      end

      test "omits the kitchen fund link for Clear Lake bookings" do
        html = render_for(unquote(mod), :clear_lake)
        refute html =~ @fund_url
      end
    end
  end

  defp render_for(mod, property) do
    user = user_fixture()

    booking =
      %{user_id: user.id, property: property}
      |> booking_fixture()
      |> Repo.preload([:user, :rooms])

    booking |> mod.prepare_email_data() |> mod.render()
  end
end
