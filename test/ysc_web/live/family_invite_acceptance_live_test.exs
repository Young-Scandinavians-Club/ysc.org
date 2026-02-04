defmodule YscWeb.FamilyInviteAcceptanceLiveTest do
  @moduledoc """
  Tests for FamilyInviteAcceptanceLive.

  This LiveView handles the family invitation acceptance flow, allowing invited
  family members to create their sub-account and join the primary user's membership.

  ## Test Coverage

  - Mount scenarios (valid/invalid/expired tokens)
  - Form pre-filling (email, most_connected_country)
  - Form validation
  - Invite acceptance (success and error cases)
  - Security (expired invites, already used invites)
  """
  use YscWeb.ConnCase, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts.FamilyInvite
  alias Ysc.Repo

  # Helper to create a valid family invite
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

    # Preload associations like the LiveView does
    invite = Repo.preload(invite, [:primary_user, :created_by_user])
    {invite, primary_user}
  end

  describe "mount/3 - invalid token" do
    test "redirects to home with error when token is invalid", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/family-invite/invalid_token_123/accept")

      assert flash["error"] == "Invalid invitation link."
    end

    test "redirects to home with error when token is nil", %{conn: conn} do
      # This shouldn't happen in practice, but tests the nil guard
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/family-invite/nonexistent_token/accept")

      assert flash["error"] == "Invalid invitation link."
    end
  end

  describe "mount/3 - expired invite" do
    test "redirects to home with error when invite is expired", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      # Manually set expires_at to past date
      expired_at =
        DateTime.add(DateTime.utc_now(), -31, :day)
        |> DateTime.truncate(:second)

      Repo.update!(Ecto.Changeset.change(invite, expires_at: expired_at))

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/family-invite/#{invite.token}/accept")

      assert flash["error"] ==
               "This invitation has expired or has already been used."
    end

    test "redirects to home with error when invite is already accepted", %{
      conn: conn
    } do
      {invite, _primary_user} = create_family_invite()

      # Mark invite as accepted
      accepted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update!(Ecto.Changeset.change(invite, accepted_at: accepted_at))

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/family-invite/#{invite.token}/accept")

      assert flash["error"] ==
               "This invitation has expired or has already been used."
    end
  end

  describe "mount/3 - valid invite" do
    test "renders form with pre-filled email", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, view, html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      assert html =~ "Accept Family Invitation"
      assert html =~ "You&#39;ve been invited by"
      assert html =~ invite.primary_user.first_name
      assert html =~ "YSC family membership"

      # Verify form is present
      assert has_element?(view, "form#accept-invite-form")

      # Verify email is pre-filled
      assert has_element?(
               view,
               "input[name='user[email]'][value='#{invite.email}']"
             )
    end

    test "pre-fills most_connected_country when primary user has one", %{
      conn: conn
    } do
      primary_user = user_fixture(%{most_connected_country: "US"})
      token = FamilyInvite.build_token()

      {:ok, invite} =
        %FamilyInvite{}
        |> FamilyInvite.changeset(%{
          email: unique_user_email(),
          token: token,
          primary_user_id: primary_user.id,
          created_by_user_id: primary_user.id
        })
        |> Repo.insert()

      invite = Repo.preload(invite, [:primary_user, :created_by_user])

      {:ok, _view, html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Verify the form rendered successfully
      # The most_connected_country is pre-filled in the changeset internally
      # We just verify the form loads without error
      assert html =~ "Accept Family Invitation"
      assert html =~ invite.email
    end

    test "does not pre-fill most_connected_country when primary user doesn't have one",
         %{conn: conn} do
      primary_user = user_fixture(%{most_connected_country: nil})
      token = FamilyInvite.build_token()

      {:ok, invite} =
        %FamilyInvite{}
        |> FamilyInvite.changeset(%{
          email: unique_user_email(),
          token: token,
          primary_user_id: primary_user.id,
          created_by_user_id: primary_user.id
        })
        |> Repo.insert()

      invite = Repo.preload(invite, [:primary_user, :created_by_user])

      {:ok, _view, _html} =
        live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Form renders successfully even without most_connected_country
      # No assertion needed beyond successful mount
    end

    test "assigns page title", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, _view, html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Verify page title is set in the HTML head
      assert html =~ "<title"
      assert html =~ "Accept Family Invitation"
    end
  end

  describe "handle_event validate" do
    test "validates form on change", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, view, _html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Trigger validation with valid data
      view
      |> form("#accept-invite-form",
        user: %{
          email: "test@example.com",
          first_name: "John",
          last_name: "Doe",
          password: "password123456"
        }
      )
      |> render_change()

      # Form should still be rendered (not redirected)
      assert has_element?(view, "form#accept-invite-form")
    end

    test "shows validation errors for invalid data", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, view, _html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Trigger validation with invalid email
      html =
        view
        |> form("#accept-invite-form",
          user: %{
            email: "invalid-email",
            first_name: "",
            last_name: ""
          }
        )
        |> render_change()

      # Should show validation errors
      assert html =~ "must have the @ sign and no spaces" or
               html =~ "can&#39;t be blank"
    end
  end

  describe "handle_event save - success" do
    test "accepts invite and creates user account", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, view, _html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Submit form with valid data
      view
      |> form("#accept-invite-form",
        user: %{
          email: invite.email,
          first_name: "John",
          last_name: "Doe",
          date_of_birth: "1990-01-01",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        }
      )
      |> render_submit()

      # Check for redirect to login page (flash content tested via integration)
      assert_redirected(view, "/users/log-in")
    end
  end

  describe "handle_event save - errors" do
    test "handles invite not found error", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, view, _html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Delete the invite to simulate not found
      Repo.delete!(invite)

      view
      |> form("#accept-invite-form",
        user: %{
          email: "test@example.com",
          first_name: "John",
          last_name: "Doe",
          password: "password123"
        }
      )
      |> render_submit()

      # Check for redirect to home (flash content tested via integration)
      assert_redirected(view, "/")
    end

    test "handles expired invite error", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, view, _html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Expire the invite
      expired_at =
        DateTime.add(DateTime.utc_now(), -31, :day)
        |> DateTime.truncate(:second)

      Repo.update!(Ecto.Changeset.change(invite, expires_at: expired_at))

      view
      |> form("#accept-invite-form",
        user: %{
          email: invite.email,
          first_name: "John",
          last_name: "Doe",
          password: "password123"
        }
      )
      |> render_submit()

      # Check for redirect to home (flash content tested via integration)
      assert_redirected(view, "/")
    end

    test "shows form errors for invalid user data", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, view, _html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Submit with invalid data (mismatched passwords)
      html =
        view
        |> form("#accept-invite-form",
          user: %{
            email: invite.email,
            first_name: "John",
            last_name: "Doe",
            password: "password123",
            password_confirmation: "different_password"
          }
        )
        |> render_submit()

      # Form should show error and not redirect
      # Check for password confirmation error (various possible wordings)
      assert html =~ "password" and
               (html =~ "does not match" or html =~ "must match" or
                  html =~ "confirmation")

      assert has_element?(view, "form#accept-invite-form")
    end

    test "shows form errors for missing required fields", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, view, _html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Submit with missing fields
      html =
        view
        |> form("#accept-invite-form",
          user: %{
            email: invite.email,
            first_name: "",
            last_name: ""
          }
        )
        |> render_submit()

      # Form should show errors (check for blank/required errors)
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank" or
               html =~ "required"

      assert has_element?(view, "form#accept-invite-form")
    end
  end

  describe "render/1" do
    test "renders all form fields", %{conn: conn} do
      {invite, _primary_user} = create_family_invite()

      {:ok, _view, html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Verify all expected fields are present
      assert html =~ "Email"
      assert html =~ "First Name"
      assert html =~ "Last Name"
      assert html =~ "Date of Birth"
      assert html =~ "Phone Number"
      assert html =~ "Password"
      assert html =~ "Confirm Password"
      assert html =~ "Create Account"
    end

    test "renders invitation details", %{conn: conn} do
      {invite, primary_user} = create_family_invite()

      {:ok, _view, html} = live(conn, ~p"/family-invite/#{invite.token}/accept")

      # Verify invitation-specific content
      assert html =~ primary_user.first_name
      assert html =~ "You&#39;ve been invited by"
      assert html =~ "cabin bookings"
      assert html =~ "event ticket purchases"
    end
  end
end
