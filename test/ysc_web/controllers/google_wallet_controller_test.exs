defmodule YscWeb.GoogleWalletControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  defp user_with_membership do
    user_fixture()
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()
    |> Ysc.Repo.reload!()
  end

  describe "GET /wallet/membership/google" do
    test "redirects unauthenticated users to the login page", %{conn: conn} do
      conn = get(conn, ~p"/wallet/membership/google")

      assert redirected_to(conn) =~ "/users/log"
    end

    test "returns 404 when the user has no active membership", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/wallet/membership/google")

      assert response(conn, 404)
    end

    test "returns 404 when Google Wallet is not configured", %{
      conn: conn
    } do
      user = user_with_membership()
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/wallet/membership/google")

      assert response(conn, 404)
    end
  end
end
