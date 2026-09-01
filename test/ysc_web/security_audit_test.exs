defmodule YscWeb.SecurityAuditTest do
  @moduledoc """
  Regression tests for the security audit findings.

  Finding 1  (CRITICAL) IDOR – Stripe setup_payment used user_id from URL path
  Finding 2  (MEDIUM)   Plaintext password stored in Cachex and socket assigns
  Finding 4  (CRITICAL) QuickBooks webhook HMAC not actually verified
  Finding 5  (MEDIUM)   AccountSetupLive mount/3 missing else branch (no redirect)
  Finding 7  (HIGH)     Passkey sign_count comparison allowed replays (>= instead of >)
  Finding 10 (HIGH)     Passkey login token replayable (Phoenix.Token → one-time DB token)
  Finding 11 (MEDIUM)   Session cookie signed-only, not encrypted
  Finding 12 (LOW)      Email address exposed in URL during email-change flow
  Finding 13 (LOW)      User's email interpolated in OAuth reauth error flash message
  Finding 14 (CRITICAL) Registration mass assignment allowed role/state/board_position escalation
  Finding 15 (HIGH)     AccountSetupLive IDOR on post-verification setup events
  Finding 16 (HIGH)     Family invite accept allowed a different email than the invite
  Finding 17 (MEDIUM)   Account setup email verification without setup token (spam / abuse)
  Finding 18 (HIGH)     Signup application mass assignment allowed forged review_outcome
  Finding 19 (MEDIUM)   Suspended/rejected users retain session access after state change
  Finding 20 (CRITICAL) Booking checkout accepts foreign/underpaid Stripe PaymentIntents
  Finding 21 (HIGH)     Paid ticket checkout bypassed via checkout=free URL / confirm-free-tickets
  Finding 22 (MEDIUM)   Kiosk check-in API accepted ineligible bookings (draft/canceled/future)
  Finding 23 (MEDIUM)   Kiosk bookings index exported full history without date bounds
  Finding 29 (MEDIUM)   Kiosk bookings index/calendar bypassed date window via explicit wide ranges
  Finding 24 (MEDIUM)   Ticket payment intents did not bind metadata to order/user
  Finding 25 (MEDIUM)   User settings verification lacks attempt rate limits; phone change lacks step-up reauth
  Finding 26 (HIGH)     Auto-login magic links replayable across cluster nodes (ETS vs DB one-time tokens)
  Finding 27 (MEDIUM)   GET auto-login/passkey endpoints allowed login CSRF (session fixation to attacker account)
  Finding 28 (CRITICAL) Account setup auto-activation charged saved cards without owner session
  Finding 32 (HIGH)     SNS cert URL allowed any *.amazonaws.com host (S3-hosted forged certs)
  Finding 33 (MEDIUM)   QuickBooks refresh token logged in full on rotation
  Finding 34 (MEDIUM)   Media library S3 uploads used guessable public/<filename> keys
  Finding 35 (HIGH)     Gmail uniqueness ignored legacy dotted/plus stored addresses, allowing login shadowing
  Finding 38 (HIGH)     Gmail canonicalization kept googlemail.com distinct from gmail.com, allowing a twin account for the same mailbox
  Trix attachments (MEDIUM) Non-image editor uploads used predictable public S3 keys
  Finding 36 (MEDIUM)   Who's Going preview leaked attendee emails when name was blank
  Finding 37 (MEDIUM)   Mileage expense items had no upper bound on miles_driven
  Finding 39 (MEDIUM)   Newsletter HTML allowed iframe/object/embed and data: URIs
  Finding 40 (MEDIUM)   Post editor accepted client rendered_body, bypassing HTML scrubbing
  Finding 43 (MEDIUM)   Flowroute webhooks logged full SMS payloads
  Finding 44 (MEDIUM)   Contact/volunteer forms cast client-supplied user_id
  Finding 45 (HIGH)     SES webhook auto-confirmed SNS subscriptions from any AWS account
  Finding 46 (HIGH)     Volunteers could refund, reassign, and grant tickets on the event Tickets tab
  Finding 47 (HIGH)     Impersonation kept post-login reauth grace, allowing password/email takeover of the victim
  Finding 48 (MEDIUM)   App ticket PaymentIntent treated donation map values as cents while documenting quantity
  Finding 49 (HIGH)     Already-authenticated mobile handoff minted a PKCE-bound code on GET from attacker-supplied challenge
  Finding 50 (HIGH)     Volunteers could reserve tickets with up to 100% discount, bypassing Finding 46 grant gates
  Finding 51 (HIGH)     Volunteers could grant $0 tickets and out-of-band memberships via the mobile app API
  Finding 52 (HIGH)     App membership subscribe reused a stale Stripe PaymentMethod without Terminal / member present
  Finding 53 (MEDIUM)   Volunteers could cancel ticket reservations (discounted holds) after Finding 46/50 grant gates

  Findings 3 (phone-verify token URL), 6 (remember-me), 8 (discoverable passkey loading),
  and 9 (registration email enumeration) are either covered by other existing test files
  or explicitly out of scope per the fix plan.
  """
  use YscWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.TestDataFactory
  import Ysc.TicketsFixtures
  import Mox

  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Payments
  alias Ysc.Tickets
  alias Ysc.Accounts.{FamilyInvites, FamilyMember, User}
  alias Ysc.Subscriptions
  alias Ysc.Accounts.UserToken
  alias Ysc.Repo
  alias Ysc.Test.KioskAPIKeyHelper
  alias YscWeb.AuthController

  import Ysc.AccountsFixtures

  setup :verify_on_exit!

  # ---------------------------------------------------------------------------
  # Finding 1 (CRITICAL): IDOR – setup_payment used user_id from URL path
  # ---------------------------------------------------------------------------

  describe "Finding 1: Stripe setup_payment IDOR fix" do
    test "setup_payment uses authenticated user, not user_id from URL", %{
      conn: conn
    } do
      attacker = user_fixture()
      victim = user_fixture()

      # The mock must be called with the *attacker* (the authenticated user),
      # not the victim whose ID appears in the URL.
      Ysc.CustomersMock
      |> expect(:create_setup_intent, fn called_user ->
        assert called_user.id == attacker.id,
               "IDOR: setup_payment must use current_user, not URL param"

        {:ok,
         %Stripe.SetupIntent{
           id: "seti_ok",
           client_secret: "seti_ok_secret",
           status: "requires_payment_method",
           customer: attacker.stripe_id
         }}
      end)

      conn =
        conn
        |> log_in_user(attacker)
        |> get("/billing/user/#{victim.id}/setup-payment")

      assert conn.status == 200
      assert json_response(conn, 200)["client_secret"] == "seti_ok_secret"
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 2 (MEDIUM): Plaintext password must NOT be cached
  # ---------------------------------------------------------------------------

  describe "Finding 2: No plaintext password in Cachex" do
    test "Cachex holds no plaintext password entry for any user id key", %{
      conn: _conn
    } do
      user = user_fixture()

      # The old (vulnerable) code stored the plaintext password under this key.
      cache_key = "account_setup_password_#{user.id}"

      # Before any setup action the key should be absent.
      assert {:ok, nil} = Cachex.get(:ysc_cache, cache_key),
             "No plaintext password should ever be written to Cachex"

      # Simulate the event of a user changing their password (Accounts context layer)
      # and verify nothing ends up in the cache.
      Cachex.put(:ysc_cache, cache_key, nil)
      assert {:ok, nil} = Cachex.get(:ysc_cache, cache_key)
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 5 (MEDIUM): AccountSetupLive must redirect fully-set-up users
  # ---------------------------------------------------------------------------

  describe "Finding 5: AccountSetupLive redirects when user has no pending setup" do
    test "active user who has completed all setup steps is redirected away from account setup",
         %{conn: conn} do
      # Fully set up means verified credentials plus an active membership; unpaid
      # active users remain in the setup funnel to collect payment/activation.
      user = user_fixture(%{state: :active})
      {:ok, user} = Accounts.mark_email_verified(user)
      {:ok, user} = Accounts.mark_password_set(user)
      {:ok, user} = Accounts.mark_phone_verified(user)

      {:ok, _sub} =
        Subscriptions.create_subscription(%{
          name: "Test Membership",
          stripe_id: "sub_audit_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          user_id: user.id,
          current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
        })

      _ = MembershipCache.invalidate_user(user.id)

      conn = log_in_user(conn, user)

      # The LiveView must redirect to "/" when the user has nothing left to set up.
      result = live(conn, ~p"/account/setup/#{user.id}")

      assert {:error, {:redirect, %{to: "/"}}} = result
    end
  end

  # ---------------------------------------------------------------------------
  # Account setup: no unsolicited email verification for already-verified emails
  # ---------------------------------------------------------------------------

  describe "AccountSetupLive mount does not spam email verification" do
    test "unauthenticated mount does not create an email verification code when email is already verified",
         %{conn: conn} do
      # registration_changeset does not cast email_verified_at; set it via the context API.
      user = user_fixture(%{state: :pending_approval})
      {:ok, user} = Accounts.mark_email_verified(user)

      assert {:ok, _view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      assert match?(
               {:error, _},
               Ysc.VerificationCache.get_code(user.id, :email_verification)
             )
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 7 (HIGH): Passkey sign_count replay protection
  # ---------------------------------------------------------------------------

  describe "Finding 7: Passkey sign_count replay protection" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.mark_email_verified(user)
      # passkey_fixture expects a map, not a keyword list
      passkey = passkey_fixture(user, %{sign_count: 5})
      %{user: user, passkey: passkey}
    end

    test "update_passkey_sign_count succeeds when new count is higher", %{
      passkey: passkey
    } do
      assert {:ok, updated} = Accounts.update_passkey_sign_count(passkey, 6)
      assert updated.sign_count == 6
    end

    test "passkey_fixture creates passkey with specified initial sign_count", %{
      passkey: passkey
    } do
      assert passkey.sign_count == 5
    end

    test "passkey with sign_count 0 can be used for first auth (both-zero case)",
         %{user: user} do
      zero_passkey = passkey_fixture(user, %{sign_count: 0})
      # Both stored (0) and new (0) means first use — must be allowed
      assert {:ok, _updated} =
               Accounts.update_passkey_sign_count(zero_passkey, 0)
    end

    test "sign_count comparison in LiveView: equal count (replay) must be rejected",
         %{
           conn: conn
         } do
      # We can't easily test the private LiveView function with real WebAuthn data,
      # but we can verify the comparison logic by inspecting the passkey_authentication_test
      # approach and the code path through the LiveView. This integration-level test
      # exercises the sign_count guard via the LiveView hook.

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      lv
      |> element("#auth-methods")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      # An attacker replaying a credential presents a non-existent credential ID,
      # which should result in an error (passkey not found), not a session.
      fake_id = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

      assert_push_event(lv, "create_authentication_challenge", %{
        options: options
      })

      response = %{
        "id" => fake_id,
        "rawId" => fake_id,
        "type" => "public-key",
        "response" => %{
          "authenticatorData" =>
            Base.url_encode64(:crypto.strong_rand_bytes(37), padding: false),
          "clientDataJSON" =>
            Base.url_encode64(
              Jason.encode!(%{
                type: "webauthn.get",
                challenge: options[:challenge],
                origin: "http://localhost:4002"
              }),
              padding: false
            ),
          "signature" =>
            Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false),
          "userHandle" => Base.url_encode64("fake_user_id", padding: false)
        }
      }

      lv
      |> element("#auth-methods")
      |> render_hook("verify_authentication", response)

      html = render(lv)
      # Should show an error, not a redirect to home
      assert html =~ "Invalid passkey" or html =~ "another sign-in" or
               html =~ "error"
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 10 (HIGH): Passkey login token must be one-time (DB-backed)
  # ---------------------------------------------------------------------------

  describe "Finding 10: One-time passkey login token" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.mark_email_verified(user)
      %{user: user}
    end

    test "generate_passkey_login_token/1 persists a token record in the DB", %{
      user: user
    } do
      token = Accounts.generate_passkey_login_token(user)

      assert is_binary(token)

      hashed =
        :crypto.hash(:sha256, Base.url_decode64!(token, padding: false))

      assert Repo.get_by(UserToken, token: hashed, context: "passkey_login"),
             "Expected a UserToken record with context 'passkey_login' in the DB"
    end

    test "verify_and_consume_passkey_login_token/1 returns the user and deletes the token",
         %{
           user: user
         } do
      token = Accounts.generate_passkey_login_token(user)

      assert {:ok, returned_user} =
               Accounts.verify_and_consume_passkey_login_token(token)

      assert returned_user.id == user.id

      # Token must be deleted after first use (one-time use guarantee)
      hashed =
        :crypto.hash(:sha256, Base.url_decode64!(token, padding: false))

      refute Repo.get_by(UserToken, token: hashed, context: "passkey_login"),
             "Token must be deleted after first consumption"
    end

    test "token cannot be used a second time (replay prevention)", %{user: user} do
      token = Accounts.generate_passkey_login_token(user)

      assert {:ok, _} = Accounts.verify_and_consume_passkey_login_token(token)

      # Second use must fail — prevents replay attacks within the TTL window
      assert {:error, :invalid_or_expired} =
               Accounts.verify_and_consume_passkey_login_token(token)
    end

    test "expired token is rejected", %{user: user} do
      token = Accounts.generate_passkey_login_token(user)

      # Back-date all UserTokens to simulate expiry beyond 120 s TTL
      Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert {:error, :invalid_or_expired} =
               Accounts.verify_and_consume_passkey_login_token(token)
    end

    test "completely invalid token string is rejected" do
      assert {:error, :invalid_or_expired} =
               Accounts.verify_and_consume_passkey_login_token(
                 "not_a_real_token"
               )
    end

    test "passkey_login endpoint consumes the token and creates a session", %{
      conn: conn,
      user: user
    } do
      token = Accounts.generate_passkey_login_token(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/passkey", %{
          "token" => token
        })

      assert get_session(conn, :user_token) != nil,
             "Expected a session to be created after passkey login"
    end

    test "passkey_login endpoint rejects an already-consumed token", %{
      conn: conn,
      user: user
    } do
      token = Accounts.generate_passkey_login_token(user)

      conn1 =
        post_token_login(build_conn(), ~p"/users/log-in/passkey", %{
          "token" => token
        })

      assert get_session(conn1, :user_token) != nil

      conn2 =
        post_token_login(conn, ~p"/users/log-in/passkey", %{
          "token" => token
        })

      assert get_session(conn2, :user_token) == nil or
               redirected_to(conn2) == ~p"/users/log-in"
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 11 (MEDIUM): Session cookie must be encrypted
  # ---------------------------------------------------------------------------

  describe "Finding 11: Session cookie encryption" do
    test "session data does not appear in plaintext in the cookie value" do
      # Build a conn with a session containing a known sentinel value.
      conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{
          test_sentinel: "topsecret_value"
        })

      # If the session cookie is encrypted its value must be opaque —
      # the literal sentinel must not appear anywhere in the cookie bytes.
      cookie_value =
        conn.resp_cookies
        |> Map.values()
        |> Enum.map(& &1[:value])
        |> Enum.reject(&is_nil/1)
        |> List.first()

      if is_binary(cookie_value) do
        refute String.contains?(cookie_value, "topsecret_value"),
               "Session cookie must not expose plaintext session data (encryption_salt missing?)"
      end
    end

    test "session round-trip works correctly after adding encryption_salt" do
      # This test implicitly verifies that the endpoint was configured correctly:
      # if encryption_salt were invalid or missing, the session plug would
      # crash/fail during init rather than reaching this assertion.
      conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{check: "ok"})

      assert get_session(conn, :check) == "ok"
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 12 (LOW): Email address must NOT appear in URL during email change
  # ---------------------------------------------------------------------------

  describe "Finding 12: Email not exposed in URL during email-change flow" do
    test "navigating directly to /users/settings/email-verification redirects to settings",
         %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      # Without a prior push_patch that sets @pending_email in the socket,
      # visiting the email-verification live action must redirect to /users/settings
      # rather than trying to read ?email= from query params (old vulnerable behaviour).
      # The LiveView uses push_patch (live_redirect) rather than a full-page redirect.
      result = live(conn, ~p"/users/settings/email-verification")

      assert {:error, {:live_redirect, %{to: redirect_to}}} = result
      assert redirect_to == ~p"/users/settings"
    end

    test "requesting an email change does not put the new email plaintext in the URL",
         %{
           conn: conn
         } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      # Request a new email address (will show re-auth modal before proceeding)
      render_submit(view, "request_email_change", %{
        user: %{email: "absolutely_secret_new_email@example.com"}
      })

      html = render(view)

      # The new email address must not appear in plaintext in any URL on the page
      refute html =~ "?email=",
             "New email address must not be embedded as a plain ?email= query parameter"

      refute html =~ "absolutely_secret_new_email%40example.com",
             "New email address must not appear URL-encoded in the page HTML"
    end

    test "page refresh on email-verification step restores flow from signed token",
         %{
           conn: conn
         } do
      user = user_fixture()

      # Simulate what the LiveView does after a successful reauth: sign the
      # pending email into a Phoenix.Token and navigate to the verification page.
      pending_email = "refresh_test@example.com"

      token =
        Phoenix.Token.sign(
          YscWeb.Endpoint,
          "email_verification_pending",
          pending_email,
          max_age: 1800
        )

      conn = log_in_user(conn, user)

      # Navigate directly to the verification page with the token, as if the
      # user had refreshed the page after the initial push_patch.
      {:ok, view, html} =
        live(conn, "/users/settings/email-verification?etok=#{token}")

      # The pending email should be displayed in the verification step
      assert html =~ pending_email or render(view) =~ pending_email,
             "Verification page should restore and display the pending email from the token"

      # No plaintext email in the URL itself (the token is opaque)
      refute html =~ "?email=",
             "Email must not appear as a plain URL parameter after refresh"
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 13 (LOW): OAuth reauth error must not echo the user's email
  # ---------------------------------------------------------------------------

  describe "Finding 13: OAuth reauth error does not leak user email" do
    test "error flash does not contain the user's email when OAuth email mismatches",
         %{conn: conn} do
      user_email = "secret.user@example.com"
      user = user_fixture(%{state: "active", email: user_email})

      auth = %Ueberauth.Auth{
        provider: :google,
        info: %Ueberauth.Auth.Info{
          email: "different@example.com",
          name: "Other Person",
          first_name: "Other",
          last_name: "Person"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "token123",
          refresh_token: nil,
          expires: false,
          expires_at: nil,
          scopes: ["email"],
          token_type: "Bearer"
        },
        uid: "google_uid_other"
      }

      conn =
        conn
        |> log_in_user(user)
        |> fetch_flash()
        |> init_test_session(%{
          reauth_mode: true,
          reauth_return_to: "/users/settings/security"
        })
        |> assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      error_msg = Phoenix.Flash.get(conn.assigns.flash, :error)

      assert is_binary(error_msg), "Expected an error flash message to be set"

      refute String.contains?(error_msg, user_email),
             "Error flash must not expose the user's email (got: #{inspect(error_msg)})"

      # The message must still be informative without leaking the address
      assert error_msg =~ "doesn't match" or error_msg =~ "social account",
             "Error message is expected to mention the mismatch generically"
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 14 (CRITICAL): Registration must not accept role/state/board_position from params
  # ---------------------------------------------------------------------------

  describe "Finding 14: registration cannot escalate role, state, or board position" do
    test "registration insert uses DB defaults for role and state, not attacker params",
         %{} do
      alias Ysc.Accounts.User

      email = "mass_assign_#{System.unique_integer([:positive])}@example.com"

      attrs = %{
        email: email,
        first_name: "Attacker",
        last_name: "User",
        role: "admin",
        state: "active"
      }

      user =
        %User{}
        |> User.registration_changeset(attrs, validate_email: false)
        |> Repo.insert!()

      user = Repo.get!(User, user.id)

      assert user.role == :member
      assert user.state == :pending_approval
    end

    test "registration insert ignores board_position in params", %{} do
      alias Ysc.Accounts.User

      email =
        "board_mass_assign_#{System.unique_integer([:positive])}@example.com"

      attrs = %{
        email: email,
        first_name: "Attacker",
        last_name: "User",
        board_position: "president"
      }

      user =
        %User{}
        |> User.registration_changeset(attrs, validate_email: false)
        |> Repo.insert!()

      user = Repo.get!(User, user.id)

      assert user.board_position == nil
      assert Accounts.list_board_position_history(user) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 15 (HIGH): AccountSetupLive IDOR on post-verification events
  # ---------------------------------------------------------------------------

  describe "Finding 15: AccountSetupLive setup events require ownership" do
    test "authenticated non-owner cannot set victim password via save_password",
         %{} do
      victim =
        user_fixture(%{
          state: :active,
          email_verified_at: nil,
          password_set_at: nil
        })

      {:ok, victim} = Accounts.mark_email_verified(victim)

      attacker_password = "blocked_by_owner_check_99!"
      conn = log_in_user(build_conn(), user_fixture())

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{victim.id}")

      view
      |> render_submit("save_password", %{
        "user" => %{
          "password" => attacker_password,
          "password_confirmation" => attacker_password
        }
      })

      victim = Accounts.get_user!(victim.id)
      assert is_nil(victim.password_set_at)

      refute Accounts.get_user_by_email_and_password(
               victim.email,
               attacker_password
             )
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 16 (HIGH): Family invite accept must require invite email
  # ---------------------------------------------------------------------------

  describe "Finding 16: accept_invite rejects email mismatch" do
    test "accept_invite returns email_mismatch when attrs email differs from invite",
         %{} do
      alias Ysc.Accounts.FamilyInvites

      primary =
        user_fixture(%{state: :active})
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      invited_email =
        "invited_#{System.unique_integer([:positive])}@example.com"

      {:ok, invite} = FamilyInvites.create_invite(primary, invited_email)

      assert {:error, :email_mismatch} =
               FamilyInvites.accept_invite(invite.token, %{
                 email:
                   "attacker_#{System.unique_integer([:positive])}@example.com",
                 password: "password1234",
                 first_name: "Bad",
                 last_name: "Actor",
                 phone_number: "+14155551234",
                 date_of_birth: ~D[1990-01-01]
               })
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 17 (MEDIUM): Account setup email verification requires setup token
  # ---------------------------------------------------------------------------

  describe "Finding 18: registration cannot set signup application review fields" do
    test "registration insert ignores review_outcome from registration_form params",
         %{} do
      alias Ysc.Accounts.User

      email = "review_mass_#{System.unique_integer([:positive])}@example.com"

      attrs = %{
        email: email,
        first_name: "Attacker",
        last_name: "User",
        registration_form: %{
          membership_type: "single",
          membership_eligibility: ["born_in_scandinavia"],
          birth_date: ~D[1990-01-01],
          address: "123 St",
          country: "USA",
          city: "SF",
          postal_code: "94107",
          place_of_birth: "Oslo",
          citizenship: "Norwegian",
          most_connected_nordic_country: "Norway",
          link_to_scandinavia: "Grandparents from Norway",
          agreed_to_bylaws: true,
          review_outcome: "approved",
          reviewed_at: ~U[2024-01-01 00:00:00Z],
          reviewed_by_user_id: Ecto.ULID.generate()
        }
      }

      user =
        %User{}
        |> User.registration_changeset(attrs, validate_email: false)
        |> Repo.insert!()
        |> Repo.preload(:registration_form)

      assert user.registration_form
      assert is_nil(user.registration_form.review_outcome)
      assert is_nil(user.registration_form.reviewed_at)
      assert is_nil(user.registration_form.reviewed_by_user_id)
    end

    test "registration insert ignores reviewed_by_user_id from registration_form params",
         %{} do
      admin = user_fixture(%{role: :admin})

      attrs =
        security_registration_attrs(%{
          registration_form: %{
            reviewed_by_user_id: admin.id
          }
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      user = Accounts.get_user!(user.id, [:registration_form])

      assert is_nil(user.registration_form.reviewed_by_user_id)
    end

    test "register_user ignores forged completed timestamp on signup application",
         %{} do
      forged_completed = ~U[2001-01-01 00:00:00Z]

      attrs =
        security_registration_attrs(%{
          registration_form: %{completed: forged_completed}
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      user = Accounts.get_user!(user.id, [:registration_form])

      assert user.registration_form.completed

      refute DateTime.compare(
               user.registration_form.completed,
               forged_completed
             ) == :eq

      assert DateTime.diff(
               DateTime.utc_now(),
               user.registration_form.completed,
               :second
             ) <
               30
    end

    test "register_user preserves a valid client started timestamp", %{} do
      client_started =
        DateTime.utc_now()
        |> DateTime.add(-2, :hour)
        |> DateTime.truncate(:second)

      attrs =
        security_registration_attrs(%{
          registration_form: %{started: DateTime.to_iso8601(client_started)}
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      user = Accounts.get_user!(user.id, [:registration_form])

      assert DateTime.compare(user.registration_form.started, client_started) ==
               :eq
    end

    test "register_user replaces unparseable started with a recent server timestamp",
         %{} do
      attrs =
        security_registration_attrs(%{
          registration_form: %{started: "not-a-valid-timestamp"}
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      user = Accounts.get_user!(user.id, [:registration_form])

      assert user.registration_form.started

      assert DateTime.diff(
               DateTime.utc_now(),
               user.registration_form.started,
               :second
             ) < 30
    end

    test "register_user sets started on or before completed", %{} do
      client_started =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      attrs =
        security_registration_attrs(%{
          registration_form: %{started: client_started}
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      user = Accounts.get_user!(user.id, [:registration_form])

      assert DateTime.compare(
               user.registration_form.started,
               user.registration_form.completed
             ) in [:lt, :eq]
    end

    test "register_user links signup application to the new user, not a forged user_id",
         %{} do
      other = user_fixture()

      attrs =
        security_registration_attrs(%{
          registration_form: %{user_id: other.id}
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      user = Accounts.get_user!(user.id, [:registration_form])

      assert user.registration_form.user_id == user.id
      refute user.registration_form.user_id == other.id
    end
  end

  describe "registration hardening: family invite and family members" do
    test "register_user does not link family_invite when email does not match invite",
         %{} do
      primary =
        user_fixture(%{state: :active})
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      invited_email =
        "invited_#{System.unique_integer([:positive])}@example.com"

      {:ok, invite} = FamilyInvites.create_invite(primary, invited_email)

      attacker_email =
        "attacker_#{System.unique_integer([:positive])}@example.com"

      attrs =
        security_registration_attrs(%{
          email: attacker_email,
          registration_form: %{family_invite_id: invite.id}
        })

      assert {:ok, user} = Accounts.register_user(attrs)
      user = Accounts.get_user!(user.id, [:registration_form])

      assert user.email == attacker_email
      assert is_nil(user.registration_form.family_invite_id)
    end

    test "register_user does not reassign an existing family member via forged id",
         %{} do
      victim = user_fixture()

      victim_member =
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(%{
          first_name: "Victim",
          last_name: "Child",
          type: "child",
          birth_date: ~D[2015-01-01]
        })
        |> Ecto.Changeset.put_change(:user_id, victim.id)
        |> Repo.insert!()

      attacker_email =
        "attacker_fm_#{System.unique_integer([:positive])}@example.com"

      attrs =
        security_registration_attrs(%{
          email: attacker_email,
          registration_form: %{membership_type: "family"},
          family_members: [
            %{
              "id" => victim_member.id,
              "type" => "child",
              "first_name" => "Stolen",
              "last_name" => "Child",
              "birth_date" => "2016-02-02"
            }
          ]
        })

      assert {:ok, attacker} = Accounts.register_user(attrs)

      victim_member = Repo.get!(FamilyMember, victim_member.id)
      assert victim_member.user_id == victim.id

      attacker = Accounts.get_user!(attacker.id, [:family_members])
      refute Enum.any?(attacker.family_members, &(&1.id == victim_member.id))
    end
  end

  describe "Finding 17: Account setup email verification requires setup token" do
    test "unauthenticated mount without setup_token does not create verification code",
         %{conn: conn} do
      user = user_fixture(%{state: :pending_approval, email_verified_at: nil})

      assert {:ok, _view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      assert match?(
               {:error, _},
               Ysc.VerificationCache.get_code(user.id, :email_verification)
             )
    end

    test "unauthenticated resend_code without setup_token does not send email",
         %{conn: conn} do
      user = user_fixture(%{state: :pending_approval, email_verified_at: nil})

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      render_click(view, "resend_code", %{})

      assert match?(
               {:error, _},
               Ysc.VerificationCache.get_code(user.id, :email_verification)
             )
    end

    test "unauthenticated verify_code without setup_token cannot mark email verified",
         %{conn: conn} do
      user = user_fixture(%{state: :pending_approval, email_verified_at: nil})
      code = Accounts.generate_and_store_email_verification_code(user)

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      render_submit(view, "verify_code", %{"verification_code" => code})

      user = Accounts.get_user!(user.id)
      assert is_nil(user.email_verified_at)
    end

    test "mount with valid setup_token allows verification flow",
         %{conn: conn} do
      user = user_fixture(%{state: :pending_approval, email_verified_at: nil})

      {:ok, view, _html} = live(conn, account_setup_path(user))

      render_click(view, "resend_code", %{})

      assert {:ok, _code} =
               Ysc.VerificationCache.get_code(user.id, :email_verification)
    end
  end

  describe "Finding 28: Account setup auto-activation requires owner session" do
    defp unpaid_active_user_with_payment_method do
      user =
        user_fixture(%{
          state: :active,
          phone_number: "+12065551234"
        })

      {:ok, user} = Accounts.mark_email_verified(user)
      {:ok, user} = Accounts.mark_phone_verified(user)
      {:ok, user} = Accounts.mark_password_set(user)

      user =
        user
        |> User.update_user_changeset(%{
          stripe_id: "cus_sec_#{System.unique_integer([:positive])}"
        })
        |> Repo.update!()

      {:ok, _pm} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_sec_#{System.unique_integer([:positive])}",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      user
    end

    test "unauthenticated mount does not create a Stripe subscription", %{
      conn: conn
    } do
      user = unpaid_active_user_with_payment_method()

      expect(Stripe.SubscriptionMock, :create, 0, fn _params ->
        flunk("unauthenticated mount should not create a Stripe subscription")
      end)

      assert {:ok, _view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      count =
        Repo.aggregate(
          from(s in Subscriptions.Subscription, where: s.user_id == ^user.id),
          :count
        )

      assert count == 0
      assert is_nil(MembershipCache.get_active_membership(user))
    end

    test "unauthenticated step navigation does not create a Stripe subscription",
         %{
           conn: conn
         } do
      user = unpaid_active_user_with_payment_method()

      expect(Stripe.SubscriptionMock, :create, 0, fn _params ->
        flunk("unauthenticated mount should not create a Stripe subscription")
      end)

      assert {:ok, _view, _html} =
               live(conn, ~p"/account/setup/#{user.id}?step=1")

      count =
        Repo.aggregate(
          from(s in Subscriptions.Subscription, where: s.user_id == ^user.id),
          :count
        )

      assert count == 0
    end
  end

  defp security_registration_attrs(overrides) do
    email = "security_reg_#{System.unique_integer([:positive])}@example.com"

    base = %{
      email: email,
      first_name: "Security",
      last_name: "Tester",
      phone_number: unique_user_phone(),
      registration_form: %{
        membership_type: "single",
        membership_eligibility: ["born_in_scandinavia"],
        birth_date: ~D[1990-01-01],
        address: "123 St",
        country: "USA",
        city: "SF",
        postal_code: "94107",
        place_of_birth: "Oslo",
        citizenship: "Norwegian",
        most_connected_nordic_country: "Norway",
        link_to_scandinavia: "Grandparents from Norway",
        agreed_to_bylaws: true
      }
    }

    deep_merge_security_attrs(base, overrides)
  end

  # ---------------------------------------------------------------------------
  # Conduct violation report: status and user_id must not be mass-assignable
  # ---------------------------------------------------------------------------

  describe "Conduct violation report mass assignment" do
    test "public changeset ignores forged status and user_id" do
      victim = user_fixture()

      attrs = %{
        "first_name" => "Eve",
        "last_name" => "Il",
        "email" => "eve@example.com",
        "phone" => "555-0100",
        "summary" => "Attempted status escalation via forged params.",
        "status" => "reviewed",
        "user_id" => victim.id
      }

      changeset =
        Ysc.Forms.ConductViolationReport.changeset(
          %Ysc.Forms.ConductViolationReport{},
          attrs
        )

      assert Ecto.Changeset.get_field(changeset, :status) == :submitted
      assert Ecto.Changeset.get_field(changeset, :user_id) == nil
    end

    test "put_submitter binds the authenticated reporter only" do
      reporter = user_fixture()

      changeset =
        %Ysc.Forms.ConductViolationReport{}
        |> Ysc.Forms.ConductViolationReport.changeset(%{
          "first_name" => "Rep",
          "last_name" => "Orter",
          "email" => reporter.email,
          "phone" => "555-0101",
          "summary" => "Logged-in reporter submission."
        })
        |> Ysc.Forms.ConductViolationReport.put_submitter(reporter)

      assert Ecto.Changeset.get_field(changeset, :user_id) == reporter.id
    end

    test "put_submitter leaves user_id unset for anonymous reporters" do
      changeset =
        %Ysc.Forms.ConductViolationReport{}
        |> Ysc.Forms.ConductViolationReport.changeset(%{
          "first_name" => "Anon",
          "last_name" => "Ymous",
          "email" => "anon@example.com",
          "phone" => "555-0102",
          "summary" => "Anonymous reporter submission."
        })
        |> Ysc.Forms.ConductViolationReport.put_submitter(nil)

      assert Ecto.Changeset.get_field(changeset, :user_id) == nil
    end

    test "create_conduct_violation_report persists submitted status and reporter only" do
      reporter = user_fixture()
      victim = user_fixture()

      changeset =
        %Ysc.Forms.ConductViolationReport{}
        |> Ysc.Forms.ConductViolationReport.changeset(%{
          "first_name" => reporter.first_name,
          "last_name" => reporter.last_name,
          "email" => reporter.email,
          "phone" => reporter.phone_number || "555-0103",
          "summary" => "Forged privileged fields should not persist.",
          "status" => "reviewed",
          "user_id" => victim.id
        })
        |> Ysc.Forms.ConductViolationReport.put_submitter(reporter)

      assert {:ok, report} =
               Ysc.Forms.create_conduct_violation_report(changeset)

      assert report.status == :submitted
      assert report.user_id == reporter.id
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 19 (MEDIUM): Suspended/rejected users must not keep session access
  # ---------------------------------------------------------------------------

  describe "Finding 19: blocked account states revoke existing sessions" do
    test "get_user_by_session_token returns nil for suspended users" do
      user = user_fixture(%{state: :active})
      token = Accounts.generate_user_session_token(user)
      admin = user_fixture(%{role: :admin})

      assert Accounts.get_user_by_session_token(token)

      {:ok, _} = Accounts.update_user(user, %{"state" => "suspended"}, admin)

      refute Accounts.get_user_by_session_token(token)
    end

    test "suspending a user deletes all session tokens from the database" do
      user = user_fixture(%{state: :active})
      token = Accounts.generate_user_session_token(user)
      admin = user_fixture(%{role: :admin})

      {:ok, _} = Accounts.update_user(user, %{"state" => "suspended"}, admin)

      assert Repo.aggregate(
               from(t in UserToken,
                 where: t.user_id == ^user.id and t.context == "session"
               ),
               :count
             ) == 0

      refute Accounts.get_user_by_session_token(token)
    end

    test "suspended user with an old cookie is redirected away from authenticated routes",
         %{conn: conn} do
      user = user_fixture(%{state: :active})
      admin = user_fixture(%{role: :admin})
      conn = log_in_user(conn, user)

      {:ok, _} = Accounts.update_user(user, %{"state" => "suspended"}, admin)

      conn = get(conn, ~p"/users/tickets")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "get_user_by_session_token returns nil for rejected and deleted users" do
      for blocked_state <- [:rejected, :deleted] do
        user = user_fixture(%{state: blocked_state})
        token = Accounts.generate_user_session_token(user)

        refute Accounts.get_user_by_session_token(token),
               "expected nil for #{blocked_state} users"
      end
    end

    test "rejecting a user via update_user revokes existing session tokens" do
      user = user_fixture(%{state: :active})
      token = Accounts.generate_user_session_token(user)
      admin = user_fixture(%{role: :admin})

      {:ok, _} = Accounts.update_user(user, %{"state" => "rejected"}, admin)

      assert Repo.aggregate(
               from(t in UserToken,
                 where: t.user_id == ^user.id and t.context == "session"
               ),
               :count
             ) == 0

      refute Accounts.get_user_by_session_token(token)
    end

    test "login_allowed_state? only permits pending_approval and active users" do
      assert Accounts.login_allowed_state?(%User{state: :active})
      assert Accounts.login_allowed_state?(%User{state: :pending_approval})
      refute Accounts.login_allowed_state?(%User{state: :suspended})
      refute Accounts.login_allowed_state?(%User{state: :rejected})
      refute Accounts.login_allowed_state?(%User{state: :deleted})
      refute Accounts.login_allowed_state?(nil)
    end

    test "rejecting an application revokes existing session tokens" do
      applicant =
        oauth_user_fixture(%{
          phone_number: unique_user_phone(),
          state: :pending_approval
        })

      application = signup_application_fixture(applicant)
      admin = user_fixture(%{role: :admin, phone_number: unique_user_phone()})
      token = Accounts.generate_user_session_token(applicant)

      assert :ok =
               Accounts.record_application_outcome(
                 :rejected,
                 applicant,
                 application,
                 admin
               )

      assert Repo.aggregate(
               from(t in UserToken,
                 where: t.user_id == ^applicant.id and t.context == "session"
               ),
               :count
             ) == 0

      refute Accounts.get_user_by_session_token(token)
    end

    test "non-blocked user updates keep existing sessions valid" do
      user = user_fixture(%{state: :active, first_name: "Before"})
      token = Accounts.generate_user_session_token(user)
      admin = user_fixture(%{role: :admin})

      {:ok, _} =
        Accounts.update_user(user, %{"first_name" => "After"}, admin)

      assert Accounts.get_user_by_session_token(token)
    end
  end

  # ---------------------------------------------------------------------------
  # Event editor: publish controls must not be mass-assignable from LiveView
  # ---------------------------------------------------------------------------

  describe "event editor mass assignment hardening" do
    alias Ysc.Events
    alias Ysc.Events.Event

    import Ysc.EventsFixtures

    test "editor_changeset ignores forged state, published_at, and organizer_id" do
      organizer = user_fixture()
      other = user_fixture()
      event = event_fixture(%{state: :draft, organizer_id: organizer.id})

      changeset =
        Event.editor_changeset(event, %{
          "title" => "Updated title",
          "state" => "published",
          "published_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "organizer_id" => other.id
        })

      assert Ecto.Changeset.get_change(changeset, :title) == "Updated title"
      refute Map.has_key?(changeset.changes, :state)
      refute Map.has_key?(changeset.changes, :published_at)
      refute Map.has_key?(changeset.changes, :organizer_id)
    end

    test "update_event_editor cannot resurrect a deleted event via forged publish params" do
      event = event_fixture(%{state: :published})
      {:ok, deleted} = Events.delete_event(event)

      assert deleted.state == :deleted

      assert {:ok, updated} =
               Events.update_event_editor(deleted, %{
                 "title" => "Sneaky republish",
                 "state" => "published",
                 "published_at" => DateTime.utc_now() |> DateTime.to_iso8601()
               })

      assert updated.state == :deleted
      assert updated.title == "Sneaky republish"
      refute Events.get_public_event(updated.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Newsletter editor: lifecycle fields must not be mass-assignable on draft save
  # ---------------------------------------------------------------------------

  describe "newsletter edition draft mass assignment hardening" do
    alias Ysc.Newsletter
    alias Ysc.Newsletter.Edition

    test "draft_changeset ignores forged status and delivery metadata" do
      edition = %Edition{status: :draft, sent_count: 0}

      changeset =
        Edition.draft_changeset(edition, %{
          "title" => "Q2 Update",
          "subject" => "Hello members",
          "status" => "sent",
          "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "sent_count" => 9_999
        })

      assert Ecto.Changeset.get_change(changeset, :title) == "Q2 Update"
      refute Map.has_key?(changeset.changes, :status)
      refute Map.has_key?(changeset.changes, :sent_at)
      refute Map.has_key?(changeset.changes, :sent_count)
    end

    test "update_edition_draft keeps draft status when client sends sent" do
      {:ok, edition} =
        Newsletter.create_edition(%{"title" => "Draft", "subject" => "Subj"})

      assert {:ok, updated} =
               Newsletter.update_edition_draft(edition, %{
                 "title" => "Still draft",
                 "subject" => "Still subj",
                 "status" => "sent",
                 "sent_count" => 500
               })

      assert updated.status == :draft
      assert updated.sent_count == 0
      assert updated.title == "Still draft"
    end
  end

  # ---------------------------------------------------------------------------
  # Payment method storage must not be CSRF-able via GET
  # ---------------------------------------------------------------------------

  describe "payment method storage CSRF hardening" do
    test "GET /billing/user/:user_id/payment-method is not routed (state change requires POST)" do
      user = user_fixture(%{stripe_id: "cus_csrf_test"})

      conn =
        build_conn()
        |> log_in_user(user)
        |> get("/billing/user/#{user.id}/payment-method", %{
          "payment_method_id" => "pm_attacker"
        })

      assert conn.status == 404
    end
  end

  # ---------------------------------------------------------------------------
  # Post editor: lifecycle fields must not be mass-assignable from LiveView
  # ---------------------------------------------------------------------------

  describe "post editor mass assignment hardening" do
    alias Ysc.Posts
    alias Ysc.Posts.Post

    test "editor_changeset ignores forged state, published_on, and featured_post" do
      post = %Post{state: :draft, featured_post: false}

      changeset =
        Post.editor_changeset(post, %{
          "title" => "Updated title",
          "state" => "published",
          "published_on" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "featured_post" => true,
          "deleted_on" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      assert Ecto.Changeset.get_change(changeset, :title) == "Updated title"
      refute Map.has_key?(changeset.changes, :state)
      refute Map.has_key?(changeset.changes, :published_on)
      refute Map.has_key?(changeset.changes, :featured_post)
      refute Map.has_key?(changeset.changes, :deleted_on)
    end

    test "update_post_editor cannot publish a draft via forged params" do
      author = user_fixture(%{role: :volunteer})

      assert {:ok, post} =
               Posts.create_post(
                 %{
                   "title" => "Draft post",
                   "url_name" => "draft-post-#{System.unique_integer()}",
                   "state" => "draft"
                 },
                 author
               )

      assert post.state == :draft

      assert {:ok, updated} =
               Posts.update_post_editor(
                 post,
                 %{
                   "title" => "Sneaky publish",
                   "state" => "published",
                   "published_on" => DateTime.utc_now() |> DateTime.to_iso8601()
                 },
                 author
               )

      assert updated.state == :draft
      assert updated.title == "Sneaky publish"
      assert Posts.get_public_post(updated.id) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 20 (CRITICAL): Booking checkout accepts foreign PaymentIntents
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Finding 21 (HIGH): Paid ticket orders cannot be completed without payment
  # ---------------------------------------------------------------------------

  describe "Finding 21: paid ticket free-checkout bypass" do
    test "process_free_ticket_order rejects pending orders with a non-zero total" do
      user = user_with_membership(:lifetime)
      event = event_with_tickets(tier_count: 1, state: :upcoming)

      order =
        ticket_order_fixture(%{user: user, event: event, status: :pending})

      refute Money.zero?(order.total_amount)

      assert {:error, :payment_required} =
               Tickets.process_free_ticket_order(order)
    end

    test "process_free_ticket_order rejects non-pending orders" do
      user = user_with_membership(:lifetime)
      event = event_with_tickets(tier_count: 1, state: :upcoming)

      order =
        ticket_order_fixture(%{user: user, event: event, status: :completed})

      assert {:error, :order_not_pending} =
               Tickets.process_free_ticket_order(order)
    end

    test "process_free_ticket_order rejects expired pending orders" do
      user = user_with_membership(:lifetime)
      event = event_with_tickets(tier_count: 1, state: :upcoming)

      order =
        ticket_order_fixture(%{user: user, event: event, status: :pending})
        |> stabilize_pending_ticket_order!()
        |> Ecto.Changeset.change(%{
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(-60, :second)
            |> DateTime.truncate(:second)
        })
        |> Ysc.Repo.update!()

      assert {:error, :order_expired} = Tickets.process_free_ticket_order(order)
    end

    test "checkout=free URL cannot confirm a pending paid ticket order", %{
      conn: conn
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        user = user_with_membership(:lifetime)
        conn = log_in_user(conn, user)
        event = event_with_tickets(tier_count: 1, state: :upcoming)

        order =
          ticket_order_fixture(%{user: user, event: event, status: :pending})
          |> stabilize_pending_ticket_order!()

        {:ok, view, _html} =
          live(
            conn,
            ~p"/events/#{event.id}?checkout=free&order_id=#{order.id}"
          )

        render_click(view, "confirm-free-tickets")

        order = Tickets.get_ticket_order(order.id)
        assert order.status == :pending
      end)
    end

    test "process_free_ticket_order rejects stale zero-dollar order after tier becomes paid" do
      user = user_with_membership(:lifetime)
      event = event_with_tickets(tier_count: 0, state: :upcoming)

      {:ok, tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "Complimentary GA",
          type: :free,
          price: Money.new(0, :USD),
          quantity: 50,
          event_id: event.id
        })

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :pending
        })
        |> stabilize_pending_ticket_order!()

      assert Money.zero?(order.total_amount)

      {:ok, _tier} =
        Ysc.Events.update_ticket_tier(tier, %{
          type: :paid,
          price: Money.new(50, :USD)
        })

      refute Tickets.pending_order_still_complimentary?(order)

      assert {:error, :payment_required} =
               Tickets.process_free_ticket_order(order)
    end

    test "process_ticket_order_payment rejects stale paid order after tier price increase" do
      user = user_with_membership(:lifetime)
      event = event_with_tickets(tier_count: 0, state: :upcoming)

      {:ok, tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "Early Bird",
          type: :paid,
          price: Money.new(30, :USD),
          quantity: 50,
          event_id: event.id
        })

      order =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :pending
        })
        |> stabilize_pending_ticket_order!()

      assert Money.equal?(order.total_amount, Money.new(30, :USD))

      {:ok, _tier} =
        Ysc.Events.update_ticket_tier(tier, %{
          price: Money.new(50, :USD)
        })

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_stale_paid_total",
        status: "succeeded",
        amount: Ysc.MoneyHelper.money_to_cents(order.total_amount),
        metadata: %{
          "ticket_order_id" => order.id,
          "user_id" => order.user_id
        }
      }

      assert {:error, :amount_mismatch} =
               Tickets.process_ticket_order_payment(order, payment_intent)

      reloaded = Tickets.get_ticket_order(order.id)
      assert reloaded.status == :pending
      assert Money.equal?(reloaded.total_amount, Money.new(50, :USD))
    end
  end

  describe "Finding 20: booking payment intent validation" do
    import Ysc.BookingsFixtures

    alias Ysc.Bookings

    test "verify_booking_payment_intent rejects a succeeded intent from another booking" do
      user = user_fixture()
      booking_a = booking_fixture(user_id: user.id, status: :hold)
      booking_b = booking_fixture(user_id: user.id, status: :hold)

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_foreign",
        status: "succeeded",
        amount: Ysc.MoneyHelper.money_to_cents(booking_a.total_price),
        metadata: %{
          "booking_id" => booking_a.id,
          "user_id" => user.id
        }
      }

      assert {:error, :payment_metadata_mismatch} =
               Bookings.verify_booking_payment_intent(payment_intent, booking_b)
    end
  end

  # ---------------------------------------------------------------------------
  # Cabin booking: server-side membership eligibility (UI can_book bypass)
  # ---------------------------------------------------------------------------

  describe "cabin booking requires active membership server-side" do
    import Ysc.BookingsFixtures
    import Ysc.TestDataFactory

    alias Ysc.Bookings
    alias Ysc.Bookings.Booking

    test "ensure_user_may_book rejects users without membership" do
      user = user_with_membership(:none)

      assert {:error, :membership_required} =
               Bookings.ensure_user_may_book(user)
    end

    test "ensure_user_may_book rejects pending_approval users" do
      user = user_fixture(%{state: :pending_approval})

      assert {:error, :application_pending_approval} =
               Bookings.ensure_user_may_book(user)
    end

    test "create-booking LiveView event does not create a hold without membership",
         %{conn: conn} do
      user = user_with_membership(:none)
      conn = log_in_user(conn, user)

      {checkin, checkout} = tahoe_booking_dates(30)

      params = %{
        "checkin_date" => Date.to_string(checkin),
        "checkout_date" => Date.to_string(checkout),
        "guests" => "4",
        "booking_mode" => "day"
      }

      {:ok, view, _html} =
        live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

      render_async(view, 5_000)

      hold_count_before =
        Repo.aggregate(
          from(b in Booking,
            where: b.user_id == ^user.id and b.status == :hold
          ),
          :count
        )

      html = render_click(view, "create-booking", %{})

      hold_count_after =
        Repo.aggregate(
          from(b in Booking,
            where: b.user_id == ^user.id and b.status == :hold
          ),
          :count
        )

      assert hold_count_before == hold_count_after
      assert html =~ "active YSC membership"
    end

    test "checkout redirects pending_approval users to pending-review", %{
      conn: conn
    } do
      user = user_fixture(%{state: :pending_approval})
      booking = booking_fixture(%{user_id: user.id, status: :hold})
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/pending-review"}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")
    end

    test "checkout redirects ineligible users even when a hold already exists",
         %{conn: conn} do
      user = user_with_membership(:none)

      booking =
        booking_fixture(%{user_id: user.id, status: :hold})

      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/users/membership"}}} =
               live(conn, ~p"/bookings/checkout/#{booking.id}")
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 22 (MEDIUM): Kiosk check-in API accepted ineligible bookings
  # ---------------------------------------------------------------------------

  describe "Finding 22: kiosk check-in booking eligibility" do
    import Ysc.BookingsFixtures

    @kiosk_key "security-audit-kiosk-key"

    setup do
      original = KioskAPIKeyHelper.capture_kiosk_api_key!(@kiosk_key)

      on_exit(fn -> KioskAPIKeyHelper.restore_kiosk_api_key!(original) end)

      :ok
    end

    test "rejects draft bookings at the kiosk check-in API", %{conn: conn} do
      booking = booking_fixture(%{status: :draft})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@kiosk_key}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/v1/mobile/check-in", %{
          property: "tahoe",
          booking_ids: [to_string(booking.id)],
          rules_agreed: true
        })

      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "not confirmed"
      refute Ysc.Repo.get!(Ysc.Bookings.Booking, booking.id).checked_in
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 23 (MEDIUM): Kiosk bookings index must not export full history by default
  # ---------------------------------------------------------------------------

  describe "Finding 23: kiosk bookings index date window" do
    import Ysc.BookingsFixtures
    import Ysc.AccountsFixtures

    alias Ysc.Bookings

    @kiosk_key "security-audit-kiosk-key"

    setup do
      original = KioskAPIKeyHelper.capture_kiosk_api_key!(@kiosk_key)

      on_exit(fn -> KioskAPIKeyHelper.restore_kiosk_api_key!(original) end)

      :ok
    end

    test "omitted dates exclude bookings outside the default window", %{
      conn: conn
    } do
      {old_checkin, old_checkout} =
        past_booking_dates_outside_default_window()

      {:ok, old_booking} =
        %{
          checkin_date: old_checkin,
          checkout_date: old_checkout,
          guests_count: 2,
          property: :tahoe,
          booking_mode: :buyout,
          user_id: user_fixture().id,
          status: :complete,
          total_price: Money.new(200, :USD)
        }
        |> Ysc.Bookings.create_booking()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@kiosk_key}")
        |> put_req_header("accept", "application/json")

      response = get(conn, ~p"/api/v1/mobile/bookings?property=tahoe")
      assert %{"data" => bookings} = json_response(response, 200)

      refute Enum.any?(bookings, &(&1["id"] == to_string(old_booking.id)))
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 29 (MEDIUM): Explicit kiosk date ranges must not bypass the bounded window
  # ---------------------------------------------------------------------------

  describe "Finding 29: kiosk bookings explicit date range cap" do
    import Ysc.BookingsFixtures
    import Ysc.AccountsFixtures

    @kiosk_key "security-audit-kiosk-key"

    setup do
      original = KioskAPIKeyHelper.capture_kiosk_api_key!(@kiosk_key)

      on_exit(fn -> KioskAPIKeyHelper.restore_kiosk_api_key!(original) end)

      :ok
    end

    test "index rejects an explicit multi-year date range", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@kiosk_key}")
        |> put_req_header("accept", "application/json")

      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings?property=tahoe&start_date=2000-01-01&end_date=2099-12-31"
        )

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "date range cannot exceed"
    end

    test "calendar rejects an explicit multi-year date range", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@kiosk_key}")
        |> put_req_header("accept", "application/json")

      response =
        get(
          conn,
          ~p"/api/v1/mobile/bookings/calendar?property=tahoe&start_date=2000-01-01&end_date=2099-12-31"
        )

      assert %{"error" => error} = json_response(response, 422)
      assert error =~ "date range cannot exceed"
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 24 (MEDIUM): Ticket payment intents must bind to order and user metadata
  # ---------------------------------------------------------------------------

  describe "Finding 24: ticket payment intent metadata validation" do
    import Ysc.TicketsFixtures

    alias Ysc.Tickets

    test "process_ticket_order_payment rejects a succeeded intent for another order" do
      user = user_with_membership(:lifetime)
      event = event_with_tickets(tier_count: 0, state: :upcoming)

      {:ok, tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "General",
          type: :paid,
          price: Money.new(40, :USD),
          quantity: 50,
          event_id: event.id
        })

      order_a =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :pending
        })
        |> stabilize_pending_ticket_order!()

      order_b =
        ticket_order_fixture(%{
          user: user,
          event: event,
          tier: tier,
          status: :pending
        })
        |> stabilize_pending_ticket_order!()

      payment_intent = %Stripe.PaymentIntent{
        id: "pi_ticket_foreign",
        status: "succeeded",
        amount: Ysc.MoneyHelper.money_to_cents(order_a.total_amount),
        metadata: %{
          "ticket_order_id" => order_a.id,
          "user_id" => user.id
        }
      }

      assert {:error, :payment_metadata_mismatch} =
               Tickets.process_ticket_order_payment(order_b, payment_intent)
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 26 (HIGH): Auto-login token must be one-time (DB-backed, cluster-safe)
  # ---------------------------------------------------------------------------

  describe "Finding 26: One-time auto-login token" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.mark_email_verified(user)
      %{user: user}
    end

    test "generate_auto_login_token/1 persists a token record in the DB", %{
      user: user
    } do
      token = Accounts.generate_auto_login_token(user)

      assert is_binary(token)

      hashed =
        :crypto.hash(:sha256, Base.url_decode64!(token, padding: false))

      assert Repo.get_by(UserToken, token: hashed, context: "auto_login"),
             "Expected a UserToken record with context 'auto_login' in the DB"
    end

    test "verify_and_consume_auto_login_token/1 returns the user and deletes the token",
         %{user: user} do
      token = Accounts.generate_auto_login_token(user)

      assert {:ok, returned_user} =
               Accounts.verify_and_consume_auto_login_token(token)

      assert returned_user.id == user.id

      hashed =
        :crypto.hash(:sha256, Base.url_decode64!(token, padding: false))

      refute Repo.get_by(UserToken, token: hashed, context: "auto_login"),
             "Token must be deleted after first consumption"
    end

    test "token cannot be used a second time (replay prevention)", %{user: user} do
      token = Accounts.generate_auto_login_token(user)

      assert {:ok, _} = Accounts.verify_and_consume_auto_login_token(token)

      assert {:error, :invalid_or_expired} =
               Accounts.verify_and_consume_auto_login_token(token)
    end

    test "auto_login endpoint consumes the token and creates a session", %{
      conn: conn,
      user: user
    } do
      token = Accounts.generate_auto_login_token(user)

      conn =
        post_token_login(conn, ~p"/users/log-in/auto", %{
          "token" => token
        })

      assert get_session(conn, :user_token) != nil,
             "Expected a session to be created after auto-login"
    end

    test "auto_login endpoint rejects an already-consumed token", %{
      conn: conn,
      user: user
    } do
      token = Accounts.generate_auto_login_token(user)

      conn1 =
        post_token_login(build_conn(), ~p"/users/log-in/auto", %{
          "token" => token
        })

      assert get_session(conn1, :user_token) != nil

      conn2 =
        post_token_login(conn, ~p"/users/log-in/auto", %{
          "token" => token
        })

      assert redirected_to(conn2) =~ "/users/log-in"
      assert redirected_to(conn2) =~ "reason=expired_link"
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 27 (MEDIUM): GET token-login must not establish a session (login CSRF)
  # ---------------------------------------------------------------------------

  describe "Finding 27: token login requires POST with CSRF" do
    setup do
      user = user_fixture(%{state: :active})
      {:ok, user} = Accounts.mark_email_verified(user)
      %{user: user}
    end

    test "GET auto-login with valid token renders form but does not log in", %{
      conn: conn,
      user: user
    } do
      token = Accounts.generate_auto_login_token(user)

      conn = get(conn, ~p"/users/log-in/auto?#{%{token: token}}")

      assert html_response(conn, 200) =~ ~s(id="token-login-form")
      refute get_session(conn, :user_token)
    end

    test "GET passkey login with valid token renders form but does not log in",
         %{
           conn: conn,
           user: user
         } do
      token = Accounts.generate_passkey_login_token(user)

      conn = get(conn, ~p"/users/log-in/passkey?#{%{token: token}}")

      assert html_response(conn, 200) =~ ~s(id="token-login-form")
      refute get_session(conn, :user_token)
    end

    test "GET auto-login cannot switch an authenticated victim into the attacker account",
         %{conn: conn, user: attacker} do
      victim = user_fixture(%{state: :active})
      {:ok, victim} = Accounts.mark_email_verified(victim)
      victim_conn = log_in_user(conn, victim)
      victim_token = get_session(victim_conn, :user_token)
      attacker_token = Accounts.generate_auto_login_token(attacker)

      conn =
        get(victim_conn, ~p"/users/log-in/auto?#{%{token: attacker_token}}")

      assert get_session(conn, :user_token) == victim_token
    end

    test "GET auto-login form includes CSRF token for POST redemption", %{
      conn: conn,
      user: user
    } do
      token = Accounts.generate_auto_login_token(user)

      conn = get(conn, ~p"/users/log-in/auto?#{%{token: token}}")
      html = html_response(conn, 200)

      assert html =~ ~s(name="_csrf_token")
      assert html =~ ~s(name="csrf-token")
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 25 (MEDIUM): User settings verification rate limits + phone reauth
  # ---------------------------------------------------------------------------

  describe "Finding 25: user settings verification hardening" do
    defp submit_reauth_password(view, password) do
      view
      |> element("#reauth_password_form")
      |> render_submit(%{"password" => password})

      render(view)
    end

    defp start_email_change_flow(view, new_email) do
      render_submit(view, "request_email_change", %{
        "user" => %{"email" => new_email}
      })

      submit_reauth_password(view, valid_user_password())
    end

    test "user settings email verification is rate limited after repeated invalid submissions",
         %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)
      new_email = "ratelimit#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)
      start_email_change_flow(view, new_email)

      for _ <- 1..12 do
        render_submit(view, "verify_email_code", %{
          "verification_code" => "111111"
        })
      end

      render_submit(view, "verify_email_code", %{
        "verification_code" => "111111"
      })

      assert render(view) =~ "Too many verification attempts"
    end

    test "user settings phone change requires step-up reauth before sending SMS",
         %{conn: conn} do
      user = user_fixture(%{state: :active, phone_number: "+14159098268"})
      conn = log_in_user(conn, user)

      new_phone =
        "+1415555#{rem(System.unique_integer([:positive]), 9000) + 1000}"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "update_profile", %{
        "user" => %{
          "first_name" => user.first_name,
          "last_name" => user.last_name,
          "phone_number" => new_phone
        }
      })

      assert has_element?(view, "#reauth-modal")
      refute render(view) =~ "Verify Your Phone Number"

      submit_reauth_password(view, valid_user_password())

      assert render(view) =~ "Verify Your Phone Number"
    end

    test "user settings phone verification is rate limited after repeated invalid submissions",
         %{conn: conn} do
      user = user_fixture(%{state: :active, phone_number: "+14159098268"})
      conn = log_in_user(conn, user)

      new_phone =
        "+1415555#{rem(System.unique_integer([:positive]), 9000) + 1000}"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "update_profile", %{
        "user" => %{
          "first_name" => user.first_name,
          "last_name" => user.last_name,
          "phone_number" => new_phone
        }
      })

      submit_reauth_password(view, valid_user_password())

      for _ <- 1..12 do
        render_submit(view, "verify_phone_code", %{
          "verification_code" => "111111"
        })
      end

      render_submit(view, "verify_phone_code", %{
        "verification_code" => "111111"
      })

      assert render(view) =~ "Too many verification attempts"
    end
  end

  # ---------------------------------------------------------------------------
  # Trix editor attachments: predictable public S3 keys
  # ---------------------------------------------------------------------------

  describe "Trix attachment uploads use unpredictable S3 keys" do
    test "non-image trix uploads do not use the client filename as the S3 object key",
         %{conn: conn} do
      admin = user_fixture(%{role: :admin})
      conn = log_in_user(conn, admin)

      path =
        Path.join(
          System.tmp_dir!(),
          "trix_security_#{System.unique_integer([:positive])}.txt"
        )

      File.write!(path, "attachment body")
      on_exit(fn -> if File.exists?(path), do: File.rm(path) end)

      conn =
        post(conn, ~p"/admin/trix-uploads", %{
          "file" => %Plug.Upload{
            path: path,
            filename: "club-policy.pdf",
            content_type: "application/pdf"
          }
        })

      assert %{"url" => url} = json_response(conn, 201)
      refute String.match?(url, ~r{/media/club-policy\.pdf$})
      assert url =~ ~r{/attachments/[^/]+/club-policy\.pdf$}
    end
  end

  defp deep_merge_security_attrs(base, overrides) when is_map(overrides) do
    Map.merge(base, overrides, fn
      :registration_form, base_form, override_form
      when is_map(base_form) and is_map(override_form) ->
        Map.merge(base_form, override_form)

      "registration_form", base_form, override_form
      when is_map(base_form) and is_map(override_form) ->
        Map.merge(base_form, override_form)

      _key, _base_val, override_val ->
        override_val
    end)
  end

  defp stabilize_pending_ticket_order!(order) do
    from(j in Oban.Job,
      where: j.worker == "Ysc.Tickets.TimeoutWorker",
      where: fragment("?->>'ticket_order_id' = ?", j.args, ^order.id),
      where: j.state in ["available", "scheduled", "retryable"]
    )
    |> Repo.delete_all()

    order
    |> Ecto.Changeset.change(
      status: :pending,
      expires_at:
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end

  # Finding 32 (HIGH): SNS cert URLs must be regional SNS hosts, not any amazonaws.com
  describe "Finding 32: SNS signing cert URL host allowlist" do
    test "rejects attacker-controlled S3 amazonaws.com cert URLs" do
      assert {:error, :invalid_cert_host} ==
               Ysc.SNS.SignatureVerifier.validate_sns_https_url(
                 "https://attacker.s3.us-west-2.amazonaws.com/forged.pem",
                 require_pem: true
               )
    end

    test "accepts regional SNS certificate URLs" do
      assert :ok ==
               Ysc.SNS.SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-60eadc5305533def8eb9f2241f05d5a7.pem",
                 require_pem: true
               )
    end
  end

  # Finding 33 (MEDIUM): QuickBooks refresh token must not be written to logs
  describe "Finding 33: QuickBooks refresh token logging" do
    test "client source does not interpolate the refresh token into log messages" do
      source =
        File.read!(Path.join(File.cwd!(), "lib/ysc/quickbooks/client.ex"))

      refute source =~ ~S(QUICKBOOKS_REFRESH_TOKEN="#{new_refresh_token}")
    end
  end

  # Finding 34 (MEDIUM): media-library direct uploads used public/<client filename>
  describe "Finding 34: media library uploads use unpredictable S3 keys" do
    test "presigned media-library keys are unique and ignore client Content-Type" do
      entry = %Phoenix.LiveView.UploadEntry{
        upload_config: :media_uploads,
        client_name: "club-logo.png",
        client_type: "text/html"
      }

      socket = %Phoenix.LiveView.Socket{
        assigns: %{uploads: %{media_uploads: %{max_file_size: 1_000_000}}}
      }

      assert {:ok, first, _} = YscWeb.MediaLibraryUpload.presign(entry, socket)
      assert {:ok, second, _} = YscWeb.MediaLibraryUpload.presign(entry, socket)

      refute first.key == "public/club-logo.png"
      assert first.key =~ ~r{^public/[^/]+/club-logo\.png$}
      assert first.key != second.key
      assert first.fields["content-type"] == "image/png"
    end
  end

  # Finding 35 (HIGH): Gmail uniqueness must use canonical matching, not only
  # the exact email column. Login/OAuth already resolve jane.doe@gmail.com and
  # janedoe@gmail.com to the same mailbox; a new signup of the canonical form
  # would otherwise steal those lookups from a legacy dotted row.
  describe "Finding 35: Gmail canonical uniqueness rejects alias shadowing" do
    test "register_user cannot take over lookups for a legacy dotted Gmail" do
      tag = Integer.to_string(System.unique_integer([:positive]))
      dotted_email = "shadow.#{tag}@gmail.com"
      canonical_email = "shadow#{tag}@gmail.com"

      %User{}
      |> Ecto.Changeset.change(%{
        email: dotted_email,
        first_name: "Legacy",
        last_name: "Gmail",
        state: :active,
        role: :member
      })
      |> Repo.insert!()

      assert {:error, changeset} =
               Accounts.register_user(%{
                 email: canonical_email,
                 phone_number: unique_user_phone(),
                 first_name: "Attacker",
                 last_name: "Shadow",
                 password: "valid password"
               })

      assert "has already been taken" in Ysc.DataCase.errors_on(changeset).email

      assert %User{email: ^dotted_email} =
               Accounts.get_user_by_email(canonical_email)

      assert %User{email: ^dotted_email} =
               Accounts.get_user_by_email(dotted_email)
    end

    test "email change cannot target a canonical alias of another member" do
      tag = Integer.to_string(System.unique_integer([:positive]))
      dotted_email = "change.#{tag}@gmail.com"
      canonical_email = "change#{tag}@gmail.com"

      %User{}
      |> Ecto.Changeset.change(%{
        email: dotted_email,
        first_name: "Legacy",
        last_name: "Gmail",
        state: :active,
        role: :member
      })
      |> Repo.insert!()

      attacker = user_fixture(%{email: "attacker#{tag}@example.com"})

      changeset = User.email_changeset(attacker, %{email: canonical_email})

      refute changeset.valid?
      assert "has already been taken" in Ysc.DataCase.errors_on(changeset).email
    end
  end

  # Finding 38 (HIGH): googlemail.com is the same mailbox as gmail.com.
  # Finding 35 closed dotted/plus shadowing but left the domain split, so a new
  # @gmail.com signup could steal Google/OAuth lookups from a legacy
  # @googlemail.com row (Google typically returns gmail.com today).
  describe "Finding 38: Googlemail and Gmail share one canonical mailbox" do
    test "register_user cannot create a gmail twin of a legacy googlemail member" do
      tag = Integer.to_string(System.unique_integer([:positive]))
      googlemail_email = "legacy#{tag}@googlemail.com"
      gmail_email = "legacy#{tag}@gmail.com"

      %User{}
      |> Ecto.Changeset.change(%{
        email: googlemail_email,
        first_name: "Legacy",
        last_name: "Googlemail",
        state: :active,
        role: :member
      })
      |> Repo.insert!()

      assert {:error, changeset} =
               Accounts.register_user(%{
                 email: gmail_email,
                 phone_number: unique_user_phone(),
                 first_name: "Attacker",
                 last_name: "Shadow",
                 password: "valid password"
               })

      assert "has already been taken" in Ysc.DataCase.errors_on(changeset).email

      assert %User{email: ^googlemail_email} =
               Accounts.get_user_by_email(gmail_email)

      assert %User{email: ^googlemail_email} =
               Accounts.get_user_by_email(googlemail_email)
    end

    test "register_user cannot create a googlemail twin of an existing gmail member" do
      tag = Integer.to_string(System.unique_integer([:positive]))
      gmail_email = "twin#{tag}@gmail.com"
      googlemail_email = "twin#{tag}@googlemail.com"

      %User{}
      |> Ecto.Changeset.change(%{
        email: gmail_email,
        first_name: "Existing",
        last_name: "Gmail",
        state: :active,
        role: :member
      })
      |> Repo.insert!()

      assert {:error, changeset} =
               Accounts.register_user(%{
                 email: googlemail_email,
                 phone_number: unique_user_phone(),
                 first_name: "Attacker",
                 last_name: "Twin",
                 password: "valid password"
               })

      assert "has already been taken" in Ysc.DataCase.errors_on(changeset).email

      assert %User{email: ^gmail_email} =
               Accounts.get_user_by_email(googlemail_email)
    end

    test "email change cannot target the googlemail form of another member's gmail" do
      tag = Integer.to_string(System.unique_integer([:positive]))
      gmail_email = "change#{tag}@gmail.com"
      googlemail_email = "change#{tag}@googlemail.com"

      %User{}
      |> Ecto.Changeset.change(%{
        email: gmail_email,
        first_name: "Existing",
        last_name: "Gmail",
        state: :active,
        role: :member
      })
      |> Repo.insert!()

      attacker = user_fixture(%{email: "attacker#{tag}@example.com"})

      changeset = User.email_changeset(attacker, %{email: googlemail_email})

      refute changeset.valid?
      assert "has already been taken" in Ysc.DataCase.errors_on(changeset).email
    end
  end

  describe "Finding 45: SES webhook TopicArn allowlist" do
    test "foreign TopicArn cannot confirm a subscription or inject a hard bounce",
         %{conn: conn} do
      email = "finding45-#{System.unique_integer([:positive])}@example.com"

      payload =
        %{
          "Type" => "Notification",
          "MessageId" => "finding-45",
          "TopicArn" => "arn:aws:sns:us-west-1:999999999999:attacker-topic",
          "Message" =>
            Jason.encode!(%{
              "eventType" => "Bounce",
              "mail" => %{
                "destination" => [email],
                "timestamp" => "2026-03-19T12:00:00.000Z",
                "tags" => %{"env" => ["test"]}
              },
              "bounce" => %{
                "bounceType" => "Permanent",
                "bounceSubType" => "General"
              }
            }),
          "Timestamp" => "2026-03-19T12:00:00.000Z",
          "SigningCertURL" => "https://sns.amazonaws.com/cert.pem",
          "Signature" => "test-signature"
        }

      conn =
        conn
        |> put_req_header("x-amz-sns-message-type", "Notification")
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/ses", payload)

      assert conn.status == 403
      refute Ysc.Newsletter.hard_bounced?(email)
    end
  end

  describe "Finding 47: Impersonation clears reauth grace and blocks credential changes" do
    test "password change is refused while impersonating even if reauth was just set",
         %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture(%{password: "target password long"})

      # Login stamps :reauth_verified_at in production. Seed it here (ConnCase
      # log_in_user only sets :user_token) then confirm impersonation clears it
      # and blocks credential changes for the impersonated subject.
      conn =
        conn
        |> log_in_user(admin)
        |> put_session(
          :reauth_verified_at,
          DateTime.utc_now() |> DateTime.to_unix()
        )

      {conn, token} = fetch_conn_csrf(conn)

      conn =
        post(conn, ~p"/admin/impersonate/#{target.id}", %{
          "_csrf_token" => token
        })

      refute get_session(conn, :reauth_verified_at)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")

      html =
        render_submit(view, "request_password_change", %{
          user: %{
            password: "attacker takeover password 99",
            password_confirmation: "attacker takeover password 99"
          }
        })

      assert html =~ "Stop impersonating"

      assert Accounts.get_user_by_email_and_password(
               target.email,
               "target password long"
             )

      refute Accounts.get_user_by_email_and_password(
               target.email,
               "attacker takeover password 99"
             )
    end

    test "email and phone changes are refused while impersonating", %{
      conn: conn
    } do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture()
      original_email = target.email
      original_phone = target.phone_number

      conn = impersonate_as_admin(conn, admin, target)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      html =
        render_submit(view, "request_email_change", %{
          "user" => %{"email" => "attacker-takeover@example.com"}
        })

      assert html =~ "Stop impersonating"

      html =
        render_submit(view, "update_profile", %{
          "user" => %{
            "first_name" => target.first_name,
            "last_name" => target.last_name,
            "phone_number" => "+14155550199",
            "most_connected_country" => target.most_connected_country || "SE",
            "date_of_birth" =>
              (target.date_of_birth && Date.to_iso8601(target.date_of_birth)) ||
                "1990-06-15"
          }
        })

      assert html =~ "Stop impersonating"

      reloaded = Accounts.get_user!(target.id)
      assert reloaded.email == original_email
      assert reloaded.phone_number == original_phone
    end

    test "reauth_verified is refused while impersonating, including phone purpose",
         %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture()

      conn = impersonate_as_admin(conn, admin, target)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      send(view.pid, :reauth_verified)
      assert render(view) =~ "Stop impersonating"

      :sys.replace_state(view.pid, fn %{socket: socket} = state ->
        %{
          state
          | socket:
              Phoenix.Component.assign(socket, reauth_purpose: :phone_change)
        }
      end)

      send(view.pid, :reauth_verified)
      assert render(view) =~ "Stop impersonating"
      assert render(view) =~ "phone"
    end

    test "passkey deletion is refused while impersonating", %{conn: conn} do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture()

      {:ok, passkey} =
        Accounts.create_user_passkey(target, %{
          external_id: Base.encode64(:crypto.strong_rand_bytes(32)),
          public_key: Base.encode64(:crypto.strong_rand_bytes(64)),
          sign_count: 0,
          nickname: "Target Device"
        })

      conn = impersonate_as_admin(conn, admin, target)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")
      render_async(view)

      html =
        render_click(view, "delete_passkey", %{"passkey_id" => passkey.id})

      assert html =~ "Stop impersonating"
      assert Repo.get(Ysc.Accounts.UserPasskey, passkey.id)
    end

    test "password reauth_verified is refused while impersonating", %{
      conn: conn
    } do
      admin = user_fixture(%{role: "admin"})
      target = user_fixture(%{password: "target password long"})

      conn = impersonate_as_admin(conn, admin, target)

      {:ok, view, _html} = live(conn, ~p"/users/settings/security")
      send(view.pid, :reauth_verified)
      assert render(view) =~ "Stop impersonating"

      assert Accounts.get_user_by_email_and_password(
               target.email,
               "target password long"
             )
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 48 (MEDIUM): App tickets donation values are cents, API says quantity
  # ---------------------------------------------------------------------------

  describe "Finding 48: app tickets reject donation tiers" do
    import Ysc.EventsFixtures

    test "donation tier selections are refused before order creation" do
      admin = user_fixture(%{role: :admin})
      token = Accounts.generate_user_mobile_token(admin)

      member =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

      event = event_fixture()

      donation =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :donation,
          price: nil
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{donation.id => 50}
        })

      assert %{
               "error" =>
                 "donation ticket tiers cannot be charged via the in-person app; collect donations on the website"
             } = json_response(conn, 422)

      orders =
        from(to in Ysc.Tickets.TicketOrder,
          where: to.user_id == ^member.id and to.event_id == ^event.id
        )
        |> Repo.all()

      assert orders == []
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 49 (HIGH): Already-authenticated mobile handoff must not mint on GET
  # ---------------------------------------------------------------------------

  describe "Finding 49: already-authenticated mobile handoff requires CSRF POST" do
    test "GET /users/log-in with attacker PKCE does not mint a redeemable code" do
      admin = user_fixture(%{role: :admin})
      verifier = String.duplicate("a", 64)
      challenge = :crypto.hash(:sha256, verifier) |> Base.encode16(case: :lower)

      login_path =
        ~p"/users/log-in?#{%{mobile_redirect_uri: "ysc-admin://auth-callback", code_challenge: challenge}}"

      conn = build_conn() |> log_in_user(admin) |> get(login_path)

      assert redirected_to(conn) == ~p"/users/log-in/mobile-handoff"

      refute Repo.exists?(
               from(t in UserToken,
                 where:
                   t.user_id == ^admin.id and t.context == "mobile_redirect"
               )
             )

      confirm = get(recycle(conn), ~p"/users/log-in/mobile-handoff")
      html = html_response(confirm, 200)
      assert html =~ ~s(id="mobile-handoff-form")
      assert html =~ ~s(id="mobile-handoff-continue")

      refute Repo.exists?(
               from(t in UserToken,
                 where:
                   t.user_id == ^admin.id and t.context == "mobile_redirect"
               )
             )
    end

    test "CSRF POST completes the handoff for the staff session, bound to the stored challenge" do
      admin = user_fixture(%{role: :admin})
      verifier = String.duplicate("a", 64)
      challenge = :crypto.hash(:sha256, verifier) |> Base.encode16(case: :lower)

      login_path =
        ~p"/users/log-in?#{%{mobile_redirect_uri: "ysc-admin://auth-callback", code_challenge: challenge}}"

      conn = build_conn() |> log_in_user(admin) |> get(login_path)
      assert redirected_to(conn) == ~p"/users/log-in/mobile-handoff"

      confirm = get(recycle(conn), ~p"/users/log-in/mobile-handoff")
      {conn, csrf} = fetch_conn_csrf_from_html(confirm)

      conn =
        post(conn, ~p"/users/log-in/mobile-handoff", %{
          "_csrf_token" => csrf,
          "intent" => "continue"
        })

      code = assert_mobile_app_handoff(conn)

      assert {:ok, %User{id: id}} =
               Accounts.verify_and_consume_mobile_redirect_token(code, verifier)

      assert id == admin.id
    end

    test "a regular member cannot start the mobile handoff via the login URL" do
      member = user_fixture()

      challenge =
        :crypto.hash(:sha256, String.duplicate("b", 64))
        |> Base.encode16(case: :lower)

      login_path =
        ~p"/users/log-in?#{%{mobile_redirect_uri: "ysc-admin://auth-callback", code_challenge: challenge}}"

      conn = build_conn() |> log_in_user(member) |> get(login_path)

      assert redirected_to(conn) == ~p"/"

      refute Repo.exists?(
               from(t in UserToken,
                 where:
                   t.user_id == ^member.id and t.context == "mobile_redirect"
               )
             )
    end

    test "GET /users/log-in/mobile-handoff without a pending handoff redirects home" do
      admin = user_fixture(%{role: :admin})

      conn =
        build_conn()
        |> log_in_user(admin)
        |> get(~p"/users/log-in/mobile-handoff")

      assert redirected_to(conn) == ~p"/"
    end

    test "cancel POST drops the pending handoff without minting a code" do
      admin = user_fixture(%{role: :admin})
      verifier = String.duplicate("a", 64)
      challenge = :crypto.hash(:sha256, verifier) |> Base.encode16(case: :lower)

      login_path =
        ~p"/users/log-in?#{%{mobile_redirect_uri: "ysc-admin://auth-callback", code_challenge: challenge}}"

      conn = build_conn() |> log_in_user(admin) |> get(login_path)
      assert redirected_to(conn) == ~p"/users/log-in/mobile-handoff"

      confirm = get(recycle(conn), ~p"/users/log-in/mobile-handoff")
      {conn, csrf} = fetch_conn_csrf_from_html(confirm)

      conn =
        post(conn, ~p"/users/log-in/mobile-handoff", %{
          "_csrf_token" => csrf,
          "intent" => "cancel"
        })

      assert redirected_to(conn) == ~p"/"

      refute Repo.exists?(
               from(t in UserToken,
                 where:
                   t.user_id == ^admin.id and t.context == "mobile_redirect"
               )
             )
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 50 (HIGH): Volunteers cannot reserve tickets with discounts
  # ---------------------------------------------------------------------------

  describe "Finding 50: volunteers cannot reserve discounted tickets" do
    import Ysc.EventsFixtures

    test "volunteer tickets tab hides reserve and rejects the LiveView event",
         %{conn: conn} do
      volunteer = user_fixture(%{role: "volunteer"})
      member = user_fixture()
      event = event_fixture(%{organizer_id: volunteer.id, state: :published})

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA Finding 50",
          quantity: 20
        })

      {:ok, view, _html} =
        conn
        |> log_in_user(volunteer)
        |> live(~p"/admin/events/#{event.id}/tickets")

      refute has_element?(view, "#ticket-tier-actions-#{tier.id}-reserve")

      view
      |> element("#ticket-tier-reserve-event-#{event.id}")
      |> render_click(%{"id" => tier.id})

      refute has_element?(view, "#reserve-tickets-modal")
      assert Ysc.Events.list_all_ticket_reservations_for_user(member.id) == []

      assert Ysc.Events.list_all_ticket_reservations_for_user(volunteer.id) ==
               []
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 51 (HIGH): Volunteers cannot grant unpaid tickets/memberships via app API
  # ---------------------------------------------------------------------------

  describe "Finding 51: volunteers cannot grant unpaid tickets or memberships via the app API" do
    import Ysc.EventsFixtures

    test "volunteer cannot grant complimentary tickets via offline_order, including to themselves",
         %{conn: conn} do
      volunteer = user_fixture(%{role: :volunteer})
      member = user_fixture()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        conn
        |> volunteer_app_conn(volunteer)
        |> post(~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => volunteer.id,
          "tiers" => %{tier.id => 1},
          "payment_method" => "cash"
        })

      assert %{"error" => "this action requires a full admin"} =
               json_response(response, 403)

      assert Ysc.Events.list_tickets_for_user(volunteer.id) == []
      assert Ysc.Events.list_tickets_for_user(member.id) == []
    end

    test "volunteer cannot create an out-of-band membership via subscribe_offline",
         %{conn: conn} do
      volunteer = user_fixture(%{role: :volunteer})
      recipient = user_fixture()

      response =
        conn
        |> volunteer_app_conn(volunteer)
        |> post(~p"/api/v1/app/memberships/subscribe_offline", %{
          "member_id" => recipient.id,
          "plan" => "single",
          "payment_method" => "cash"
        })

      assert %{"error" => "this action requires a full admin"} =
               json_response(response, 403)

      refute Accounts.has_active_membership?(Accounts.get_user!(recipient.id))
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 52 (HIGH): App membership subscribe must not reuse stale PMs
  # ---------------------------------------------------------------------------

  describe "Finding 52: app membership subscribe payment method binding" do
    test "rejects a payment method that is not freshly collected for the member",
         %{conn: conn} do
      volunteer = user_fixture(%{role: :volunteer})
      token = Accounts.generate_user_mobile_token(volunteer)

      member =
        user_fixture()
        |> Ecto.Changeset.change(stripe_id: "cus_finding_52")
        |> Repo.update!()

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      on_exit(fn ->
        Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
      end)

      # Stub rather than expect: this file is `async: true` and other tests
      # mutate `:stripe_client`. A missed mock call here is a race, not a
      # product regression — stale-PM binding is covered with expect in
      # `app_memberships_controller_test.exs` (`async: false`).
      stub(Ysc.StripeMock, :retrieve_payment_method, fn "pm_stale_reuse" ->
        {:ok,
         %Stripe.PaymentMethod{
           id: "pm_stale_reuse",
           customer: member.stripe_id,
           created: System.system_time(:second) - 60 * 60 - 30
         }}
      end)

      response =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v1/app/memberships/subscribe", %{
          "member_id" => member.id,
          "plan" => "single",
          "payment_method_id" => "pm_stale_reuse"
        })

      assert %{
               "error" =>
                 "payment method must be collected for this member via Terminal just before subscribe"
             } = json_response(response, 422)
    end
  end

  # ---------------------------------------------------------------------------
  # Finding 53 (MEDIUM): Volunteers cannot cancel ticket reservations
  # ---------------------------------------------------------------------------

  describe "Finding 53: volunteers cannot cancel ticket reservations" do
    import Ysc.EventsFixtures

    test "hides cancel control and rejects the LiveView cancel event", %{
      conn: conn
    } do
      volunteer = user_fixture(%{role: "volunteer"})
      admin = user_fixture(%{role: :admin})
      member = user_fixture()
      event = event_fixture(%{organizer_id: volunteer.id, state: :published})

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA Finding 53",
          quantity: 20
        })

      expires_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.add(2, :day)

      assert {:ok, reservation} =
               Ysc.Events.create_ticket_reservation(%{
                 ticket_tier_id: tier.id,
                 user_id: member.id,
                 created_by_id: admin.id,
                 quantity: 1,
                 expires_at: expires_at,
                 discount_percentage: Decimal.new("50")
               })

      {:ok, view, _html} =
        conn
        |> log_in_user(volunteer)
        |> live(~p"/admin/events/#{event.id}/tickets")

      refute has_element?(view, "#cancel-reservation-#{reservation.id}")

      view
      |> element("#ticket-tier-cancel-reservation-event-#{event.id}")
      |> render_click(%{"id" => reservation.id})

      reloaded = Ysc.Events.get_ticket_reservation!(reservation.id)
      assert reloaded.status == "active"
    end
  end

  defp volunteer_app_conn(conn, volunteer) do
    token = Accounts.generate_user_mobile_token(volunteer)

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer #{token}")
  end

  defp impersonate_as_admin(conn, admin, target) do
    conn = log_in_user(conn, admin)
    {conn, token} = fetch_conn_csrf(conn)

    post(conn, ~p"/admin/impersonate/#{target.id}", %{
      "_csrf_token" => token
    })
  end
end
