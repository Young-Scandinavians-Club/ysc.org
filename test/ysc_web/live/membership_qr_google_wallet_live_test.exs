defmodule YscWeb.MembershipQrGoogleWalletLiveTest do
  @moduledoc """
  Regression tests for Google Wallet save-URL generation on the membership QR modal.

  Ticket QR LiveView and `GoogleWallet.generate_membership_save_url/1` already
  cover save links. This file covers the production caller
  (`MembershipQr.show/2` from HomeLive) that previously had no success-path
  coverage when credentials are present.

  Runs with async: false because credential injection mutates global app state.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.GoogleWalletCredentialsHelper

  test "home membership QR modal renders a Google Wallet save link", %{
    conn: conn
  } do
    user = Ysc.TestDataFactory.user_with_membership(:lifetime)

    with_google_wallet_credentials(fn ->
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/")
      render_async(view, 5_000)

      view
      |> element("button", "My Membership QR")
      |> render_click()

      assert has_element?(view, "#membership-qr-modal")

      html = render(view)
      assert html =~ "pay.google.com/gp/v/save/"
      assert html =~ "Add to Google Wallet"
    end)
  end
end
