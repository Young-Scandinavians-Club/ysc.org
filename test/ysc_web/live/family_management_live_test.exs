defmodule YscWeb.FamilyManagementLiveTest do
  # async: false — reload regression enables :process_caches_enabled
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyInvites
  alias Ysc.Accounts.FamilyMembers
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

  defp with_process_caches(fun) do
    previous = Application.get_env(:ysc, :process_caches_enabled, false)
    Application.put_env(:ysc, :process_caches_enabled, true)
    Cachex.clear(:ysc_cache)

    try do
      fun.()
    after
      Application.put_env(:ysc, :process_caches_enabled, previous)
      Cachex.clear(:ysc_cache)
    end
  end

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

  defp add_roster_member(user, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          "id" => "",
          "first_name" => "Alex",
          "last_name" => "Wong",
          "birth_date" => "1990-04-07",
          "relationship" => "child"
        },
        attrs
      )

    assert {:ok, member} = FamilyMembers.upsert_family_member(user, params)
    member
  end

  describe "primary account holder" do
    test "renders family management heading and add member CTA for eligible user",
         %{
           conn: conn
         } do
      user = lifetime_member()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      _ = render_loaded(view)

      assert has_element?(
               view,
               "#family-management-heading",
               "Family Management"
             )

      assert has_element?(
               view,
               "#family-member-limit",
               "Limit: 1 spouse, up to 9 children"
             )

      assert has_element?(view, "#add-family-member-button")
      assert has_element?(view, "#pending-invites-empty")
      refute has_element?(view, "#invite-form")
    end

    test "shows warning when user cannot send invites", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      html = render_loaded(view)

      assert html =~ "send family invites right now"
      assert html =~ "Invites you send will appear here"
    end

    test "opens add family member modal and saves roster member", %{conn: conn} do
      user = lifetime_member()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      view
      |> element("#add-family-member-button")
      |> render_click()

      assert has_element?(view, "#family-member-modal")
      assert has_element?(view, "#family-member-form")

      view
      |> form("#family-member-form",
        family_member: %{
          first_name: "Casey",
          last_name: "Lee",
          birth_date: "2012-06-01",
          relationship: "child"
        }
      )
      |> render_submit()

      html = render(view)
      refute has_element?(view, "#family-member-modal")
      assert html =~ "Casey Lee"
      assert html =~ "Invite pending"
      assert has_element?(view, "#active-family-members-table")
    end

    test "saved family member remains after page reload", %{conn: conn} do
      with_process_caches(fn ->
        user = lifetime_member()

        # Prime the same profile-cache key used by FamilyManagementLive load.
        _ =
          Accounts.get_user!(user.id, [
            :sub_accounts,
            :family_members,
            subscriptions: :subscription_items
          ])

        conn = log_in_user(conn, user)

        {:ok, view, _html} = live(conn, ~p"/users/settings/family")
        _ = render_loaded(view)

        view
        |> element("#add-family-member-button")
        |> render_click()

        view
        |> form("#family-member-form",
          family_member: %{
            first_name: "Pelle",
            last_name: "Svans",
            birth_date: "2020-07-02",
            relationship: "child"
          }
        )
        |> render_submit()

        assert render(view) =~ "Pelle Svans"

        {:ok, reloaded, _html} = live(conn, ~p"/users/settings/family")
        assert render_loaded(reloaded) =~ "Pelle Svans"
        assert has_element?(reloaded, "#active-family-members-table")
      end)
    end

    test "cancels add family member modal", %{conn: conn} do
      user = lifetime_member()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      view
      |> element("#add-family-member-button")
      |> render_click()

      assert has_element?(view, "#family-member-modal")

      view
      |> element("button[phx-click='cancel_family_member_form']")
      |> render_click()

      refute has_element?(view, "#family-member-modal")
    end

    test "edits an existing roster member from the unified table", %{conn: conn} do
      user = lifetime_member()
      member = add_roster_member(user)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      assert has_element?(view, "#family-member-row-#{member.id}")

      view
      |> element(
        "#family-member-row-#{member.id} button[phx-click='edit_family_member']"
      )
      |> render_click()

      assert has_element?(view, "#family-member-modal")

      view
      |> form("#family-member-form",
        family_member: %{
          id: member.id,
          first_name: "Alexandra",
          last_name: "Wong",
          birth_date: "1990-04-07",
          relationship: "child"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Alexandra Wong"
      refute has_element?(view, "#family-member-modal")
    end

    test "validate_invite updates invite modal email field", %{conn: conn} do
      user = lifetime_member()
      member = add_roster_member(user)
      conn = log_in_user(conn, user)
      email = unique_user_email()

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      view
      |> element("#invite-family-member-button-#{member.id}")
      |> render_click()

      assert has_element?(view, "#invite-family-member-modal")

      view
      |> form("#invite-family-member-form",
        invite: %{"email" => email, "family_member_id" => member.id}
      )
      |> render_change()

      assert render(view) =~ email
    end

    test "invite_family_member from modal succeeds and lists pending invitation",
         %{
           conn: conn
         } do
      user = lifetime_member()
      member = add_roster_member(user)
      conn = log_in_user(conn, user)
      email = unique_user_email()

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      view
      |> element("#invite-family-member-button-#{member.id}")
      |> render_click()

      view
      |> form("#invite-family-member-form",
        invite: %{"email" => email, "family_member_id" => member.id}
      )
      |> render_submit()

      html = render(view)
      assert html =~ email
      assert has_element?(view, "#pending-invites-table")
      refute has_element?(view, "#invite-family-member-modal")
    end

    test "invite_family_member shows error for user without family or lifetime membership",
         %{
           conn: conn
         } do
      user = user_fixture()
      member = add_roster_member(user)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      view
      |> element("#invite-family-member-button-#{member.id}")
      |> render_click()

      assert has_element?(view, "#invite-family-member-modal")
      assert has_element?(view, "#invite-family-member-disabled-notice")

      # Email input is disabled when ineligible; exercise the server error path via hook.
      view
      |> render_hook("invite_family_member", %{
        "invite" => %{
          "email" => unique_user_email(),
          "family_member_id" => member.id
        }
      })

      assert render(view) =~
               "You must have a family or lifetime membership to send invites."
    end

    test "invite_family_member shows error when account is not active", %{
      conn: conn
    } do
      user =
        user_fixture()
        |> Ecto.Changeset.change(
          state: :pending_approval,
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      member = add_roster_member(user)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      view
      |> element("#invite-family-member-button-#{member.id}")
      |> render_click()

      assert has_element?(view, "#invite-family-member-modal")

      view
      |> render_hook("invite_family_member", %{
        "invite" => %{
          "email" => unique_user_email(),
          "family_member_id" => member.id
        }
      })

      assert render(view) =~
               "Your account must be approved by the board before you can send family invitations."
    end

    test "invite_family_member shows error when a pending invite already exists for email",
         %{
           conn: conn
         } do
      user = lifetime_member()
      member = add_roster_member(user)
      email = unique_user_email()
      assert {:ok, _} = FamilyInvites.create_invite(user, email)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      view
      |> element("#invite-family-member-button-#{member.id}")
      |> render_click()

      view
      |> form("#invite-family-member-form",
        invite: %{"email" => email, "family_member_id" => member.id}
      )
      |> render_submit()

      assert render(view) =~
               "A pending invitation already exists for this email."
    end

    test "invite_family_member shows error when email is blank", %{conn: conn} do
      user = lifetime_member()
      member = add_roster_member(user)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      view
      |> render_hook("invite_family_member", %{
        "invite" => %{
          "email" => "   ",
          "family_member_id" => member.id
        }
      })

      assert render(view) =~ "Please enter an email address."
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

    test "remove_sub_account removes linked row from unified table", %{
      conn: conn
    } do
      {primary, sub} = primary_with_linked_sub()
      assert length(Accounts.get_sub_accounts(primary)) == 1

      conn = log_in_user(conn, primary)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      html = render(view)
      assert html =~ sub.email
      assert html =~ "Linked Account"
      assert has_element?(view, "#linked-family-member-row-#{sub.id}")

      view
      |> element(
        "button[phx-click='remove_sub_account'][phx-value-user_id='#{sub.id}']"
      )
      |> render_click()

      refute render(view) =~ sub.email
    end

    test "deletes roster member from unified table", %{conn: conn} do
      user = lifetime_member()
      member = add_roster_member(user)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")
      _ = render_loaded(view)

      assert has_element?(view, "#family-member-row-#{member.id}")

      view
      |> element(
        "#family-member-row-#{member.id} button[phx-click='delete_family_member']"
      )
      |> render_click()

      refute has_element?(view, "#family-member-row-#{member.id}")
    end
  end

  describe "sub-account view" do
    test "shows primary holder section and leave button", %{conn: conn} do
      {_primary, sub} = primary_with_linked_sub()
      conn = log_in_user(conn, sub)

      {:ok, view, _html} = live(conn, ~p"/users/settings/family")

      assert render_loaded(view) =~ "Family membership manager"
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
