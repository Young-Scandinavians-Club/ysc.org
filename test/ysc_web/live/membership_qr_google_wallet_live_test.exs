defmodule YscWeb.MembershipQrGoogleWalletLiveTest do
  @moduledoc """
  Regression tests for on-demand Google Wallet save links on the membership
  QR modal. JWT signing happens on GET `/wallet/membership/google`, not
  while HomeLive opens the modal.

  Runs with async: false because credential injection mutates global app state.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.GoogleWalletCredentialsHelper

  test "home membership QR modal links to the on-demand Google Wallet redirect",
       %{
         conn: conn
       } do
    user = Ysc.TestDataFactory.user_with_membership(:lifetime)

    with_google_wallet_credentials(fn ->
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/")
      render_async(view, 5_000)

      {clicked, subscription_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            Ysc.QueryCounter.track_caller_pid(view.pid)

            view
            |> element("button", "My Membership QR")
            |> render_click()
          end,
          pattern: ~r/FROM "subscriptions"/i,
          caller_pids: [self()]
        )

      assert has_element?(view, "#membership-qr-modal")
      assert subscription_queries == 0
      refute clicked =~ "pay.google.com"
      assert clicked =~ ~s(href="/wallet/membership/google")
      assert clicked =~ "Add to Google Wallet"
    end)
  end

  test "GET /wallet/membership/google redirects to a signed save URL", %{
    conn: conn
  } do
    user = Ysc.TestDataFactory.user_with_membership(:lifetime)

    with_google_wallet_credentials(fn ->
      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/wallet/membership/google")

      assert redirected_to(conn) =~ "https://pay.google.com/gp/v/save/"
    end)
  end
end
