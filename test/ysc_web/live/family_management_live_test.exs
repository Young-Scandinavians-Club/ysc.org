defmodule YscWeb.FamilyManagementLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyInvites
  alias Ysc.Repo

  defp unique_phone, do: unique_user_phone()

  defp lifetime_member(attrs \\ %{}) do
    user_fixture(attrs)
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end

  # Family data loads after WebSocket connect; use render/1 not the initial live/2 HTML.
  defp render_loaded(view), do: render(view)

  defp primary_with_linked_sub do
    primary = lifetime_member(%{phone_number: unique_phone()})
    sub = user_fixture(%{phone_number: unique_phone()})

    sub =
      sub
      |> Ecto.Changeset.change(%{})
      |> Ecto.Changeset.put_change(:primary_user_id, primary.id)
      |> Repo.update!()

    {primary, sub}
  end

  describe "primary account holder" do
    test "renders family management heading and invite form for eligible user",
         %{
           conn: conn
         } do
      user = lifetime_member()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      assert render_loaded(view) =~ "Family Management"
      assert has_element?(view, "#invite-form")
    end

    test "shows warning when user cannot send invites", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      html = render_loaded(view)

      assert html =~ "cannot send invites" or
               html =~ "cannot send invites at this time"
    end

    test "validate_invite updates form fields", %{conn: conn} do
      user = lifetime_member()
      conn = log_in_user(conn, user)
      email = unique_user_email()

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      view
      |> render_hook("validate_invite", %{
        "invite" => %{
          "email" => email,
          "relationship" => "spouse",
          "family_member_id" => ""
        }
      })

      assert render(view) =~ email
    end

    test "send_invite succeeds and lists pending invitation", %{conn: conn} do
      user = lifetime_member()
      conn = log_in_user(conn, user)
      email = unique_user_email()

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      view
      |> render_hook("send_invite", %{
        "invite" => %{
          "email" => email,
          "relationship" => "child",
          "family_member_id" => ""
        }
      })

      html = render(view)
      assert html =~ email
      assert html =~ "Pending Invitations" or html =~ "pending"
    end

    test "send_invite shows error for user without family or lifetime membership",
         %{
           conn: conn
         } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      view
      |> render_hook("send_invite", %{
        "invite" => %{
          "email" => unique_user_email(),
          "relationship" => "child",
          "family_member_id" => ""
        }
      })

      assert render(view) =~ "family or lifetime" or
               render(view) =~ "membership"
    end

    test "send_invite shows error when account is not active", %{conn: conn} do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          state: :pending_approval,
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      view
      |> render_hook("send_invite", %{
        "invite" => %{
          "email" => unique_user_email(),
          "relationship" => "child",
          "family_member_id" => ""
        }
      })

      assert render(view) =~ "active" or render(view) =~ "must be active"
    end

    test "send_invite shows error when a pending invite already exists for email",
         %{
           conn: conn
         } do
      user = lifetime_member()
      email = unique_user_email()
      assert {:ok, _} = FamilyInvites.create_invite(user, email)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      view
      |> render_hook("send_invite", %{
        "invite" => %{
          "email" => email,
          "relationship" => "child",
          "family_member_id" => ""
        }
      })

      assert render(view) =~ "already exists" or render(view) =~ "pending"
    end

    test "revoke_invite removes invite from list", %{conn: conn} do
      user = lifetime_member()
      email = unique_user_email()
      {:ok, invite} = FamilyInvites.create_invite(user, email)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      assert render(view) =~ email

      view
      |> element(
        "button[phx-click='revoke_invite'][phx-value-invite_id='#{invite.id}']"
      )
      |> render_click()

      refute render(view) =~ email
    end

    test "revoke_invite shows error for unknown invite id", %{conn: conn} do
      user = lifetime_member()
      conn = log_in_user(conn, user)
      bogus = Ecto.ULID.generate()

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      view |> render_hook("revoke_invite", %{"invite_id" => bogus})

      assert render(view) =~ "not found" or render(view) =~ "Invitation"
    end

    test "remove_sub_account removes row from table", %{conn: conn} do
      {primary, sub} = primary_with_linked_sub()
      assert length(Accounts.get_sub_accounts(primary)) == 1

      conn = log_in_user(conn, primary)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      assert render(view) =~ sub.email

      view
      |> element(
        "button[phx-click='remove_sub_account'][phx-value-user_id='#{sub.id}']"
      )
      |> render_click()

      refute render(view) =~ sub.email
    end
  end

  describe "sub-account view" do
    test "shows primary holder section and leave button", %{conn: conn} do
      {_primary, sub} = primary_with_linked_sub()
      conn = log_in_user(conn, sub)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      assert render_loaded(view) =~ "Primary Account Holder"
      assert has_element?(view, "button[phx-click='leave-family-membership']")
    end

    test "leave-family-membership redirects sub-account to membership page", %{
      conn: conn
    } do
      {_primary, sub} = primary_with_linked_sub()
      conn = log_in_user(conn, sub)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      result =
        view
        |> element("button[phx-click='leave-family-membership']")
        |> render_click()

      assert {:error, {:redirect, %{to: path}}} = result
      assert path == ~p"/users/membership"
    end

    test "leave-family-membership as primary shows error via hook", %{
      conn: conn
    } do
      user = lifetime_member()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      view |> render_hook("leave-family-membership", %{})

      assert render(view) =~ "not linked" or render(view) =~ "family membership"
    end
  end
end
