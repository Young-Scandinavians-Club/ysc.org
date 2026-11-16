defmodule YscWeb.MembershipQrTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Scanning.QrToken
  alias YscWeb.MembershipQr

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  describe "show/2" do
    test "signs a membership token and builds QR details" do
      user = %{
        id: "01HQRMEMBERSHIP000000000001",
        first_name: "Ada",
        last_name: "Lovelace",
        inserted_at: ~U[2021-01-01 00:00:00Z]
      }

      membership = %{type: :lifetime, awarded_at: ~D[2019-06-15]}

      updated =
        MembershipQr.show(
          socket(%{
            current_user: user,
            current_membership: membership,
            is_sub_account: false,
            primary_user: nil,
            google_wallet_membership_enabled?: false
          }),
          user
        )

      assert updated.assigns.show_membership_qr

      assert {:ok, {:membership, "01HQRMEMBERSHIP000000000001"}} =
               QrToken.verify(updated.assigns.membership_qr_token)

      assert updated.assigns.membership_qr_details.type_label ==
               "Lifetime Membership"

      assert updated.assigns.membership_qr_details.member_since ==
               ~D[2019-06-15]
    end

    test "does not query subscriptions when opening the modal" do
      user = user_fixture()
      membership = %{type: :lifetime, awarded_at: ~D[2019-06-15]}

      {_updated, subscription_queries} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            MembershipQr.show(
              socket(%{
                current_user: user,
                current_membership: membership,
                is_sub_account: false,
                primary_user: nil,
                google_wallet_membership_enabled?: true
              }),
              user
            )
          end,
          pattern: ~r/FROM "subscriptions"/i,
          caller_pids: [self()]
        )

      assert subscription_queries == 0
    end
  end

  describe "hide/1" do
    test "clears the modal assigns" do
      updated =
        MembershipQr.hide(
          socket(%{
            show_membership_qr: true,
            membership_qr_token: "token",
            membership_qr_details: %{type_label: "Family Membership"}
          })
        )

      refute updated.assigns.show_membership_qr
      assert updated.assigns.membership_qr_token == nil
      assert updated.assigns.membership_qr_details == nil
    end
  end
end
