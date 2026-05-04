defmodule YscWeb.FamilyInviteLogoutRequiredLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.FamilyInvite
  alias Ysc.Repo

  defp create_family_invite(attrs \\ %{}) do
    primary_user = user_fixture()
    token = FamilyInvite.build_token()

    invite_attrs =
      Enum.into(attrs, %{
        email: unique_user_email(),
        token: token,
        primary_user_id: primary_user.id,
        created_by_user_id: primary_user.id
      })

    {:ok, invite} =
      %FamilyInvite{}
      |> FamilyInvite.changeset(invite_attrs)
      |> Repo.insert()

    Repo.preload(invite, [:primary_user, :created_by_user])
  end

  describe "mount/3 when not logged in" do
    test "redirects to the invite acceptance page", %{conn: conn} do
      invite = create_family_invite()

      assert {:error, {kind, %{to: to}}} =
               live(conn, ~p"/family-invite/#{invite.token}/logout-required")

      assert kind in [:redirect, :live_redirect]
      assert to == ~p"/family-invite/#{invite.token}/accept"
    end
  end

  describe "mount/3 when logged in" do
    test "redirects home with error when token is unknown", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/family-invite/bad_token_xyz/logout-required")

      assert flash["error"] == "Invalid invitation link."
    end

    test "redirects home when invite is expired", %{conn: conn} do
      invite = create_family_invite()
      user = user_fixture()
      conn = log_in_user(conn, user)

      expired_at =
        DateTime.add(DateTime.utc_now(), -31, :day)
        |> DateTime.truncate(:second)

      Repo.update!(Ecto.Changeset.change(invite, expires_at: expired_at))

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/family-invite/#{invite.token}/logout-required")

      assert flash["error"] ==
               "This invitation has expired or has already been used."
    end

    test "shows log-in path when invite email already has an account", %{
      conn: conn
    } do
      _invited_account = user_fixture(%{email: "invited.person@example.com"})
      invite = create_family_invite(%{email: "invited.person@example.com"})
      other = user_fixture()
      conn = log_in_user(conn, other)

      {:ok, view, html} =
        live(conn, ~p"/family-invite/#{invite.token}/logout-required")

      assert html =~ "Log Out to Accept Invitation"
      assert html =~ other.email
      assert has_element?(view, "button", "Log out and log in using")
      assert render(view) =~ "/users/log-in?redirect_to=/users/membership"
    end

    test "shows create-account path when invite email has no account yet", %{
      conn: conn
    } do
      invite = create_family_invite()
      other = user_fixture()
      conn = log_in_user(conn, other)

      {:ok, view, html} =
        live(conn, ~p"/family-invite/#{invite.token}/logout-required")

      assert html =~ "Log Out to Accept Invitation"
      assert html =~ invite.email
      assert has_element?(view, "button", "Log out and continue with")

      assert render(view) =~
               ~p"/family-invite/#{invite.token}/accept"
    end

    test "logout form posts to log-out with redirect_to hidden field", %{
      conn: conn
    } do
      invite = create_family_invite()
      other = user_fixture()
      conn = log_in_user(conn, other)

      {:ok, view, _html} =
        live(conn, ~p"/family-invite/#{invite.token}/logout-required")

      assert has_element?(view, "form[action='/users/log-out'][method='post']")
      assert has_element?(view, "input[name='redirect_to']")
    end
  end
end
