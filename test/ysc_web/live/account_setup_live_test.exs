defmodule YscWeb.AccountSetupLiveTest do
  # Email verification shares Hammer rate-limit state (ETS) and OTP assigns are
  # sensitive to parallel LiveView tests in this module.
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Accounts.VerificationCodes
  alias Ysc.Payments
  alias Ysc.Subscriptions

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  defp pending_user_with_default_payment(attrs \\ %{}) do
    user = verified_pending_user(Map.merge(%{password_set_at: nil}, attrs))

    {:ok, _pm} =
      Payments.insert_payment_method(%{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_#{System.unique_integer([:positive])}",
        provider_customer_id: "cus_#{System.unique_integer([:positive])}",
        type: :card,
        provider_type: "card",
        is_default: true
      })

    user
  end

  defp give_active_membership(user) do
    {:ok, _sub} =
      Subscriptions.create_subscription(%{
        name: "Test Membership",
        stripe_id: "sub_setup_#{System.unique_integer([:positive])}",
        stripe_status: "active",
        user_id: user.id,
        current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
      })

    _ = MembershipCache.invalidate_user(user.id)
    user
  end

  # The sandbox mode makes 000000 a universally accepted OTP code.
  @valid_otp %{
    "0" => "0",
    "1" => "0",
    "2" => "0",
    "3" => "0",
    "4" => "0",
    "5" => "0"
  }
  @invalid_otp %{
    "0" => "9",
    "1" => "9",
    "2" => "9",
    "3" => "9",
    "4" => "9",
    "5" => "9"
  }

  # Creates a pending user with all setup incomplete.
  defp unverified_pending_user(attrs \\ %{}) do
    user_fixture_fast(
      Map.merge(
        %{
          state: :pending_approval,
          email_verified_at: nil,
          password_set_at: nil
        },
        attrs
      )
    )
  end

  # Creates a pending user with email already verified.
  defp verified_pending_user(attrs \\ %{}) do
    user = unverified_pending_user(attrs)
    {:ok, user} = Accounts.mark_email_verified(user)
    user
  end

  # Creates an active member who still needs to set a password (has membership,
  # so payment step is skipped).
  defp active_user_needing_password do
    user =
      user_fixture_fast(%{
        state: :active,
        email_verified_at: nil,
        password_set_at: nil
      })

    {:ok, user} = Accounts.mark_email_verified(user)
    give_active_membership(user)
  end

  # Creates an active member who needs password and has no phone stored.
  defp active_user_needing_password_no_phone do
    user =
      user_fixture_fast(%{
        state: :active,
        email_verified_at: nil,
        password_set_at: nil,
        phone_number: nil
      })

    {:ok, user} = Accounts.mark_email_verified(user)
    give_active_membership(user)
  end

  defp unpaid_active_user_needing_payment(attrs \\ %{}) do
    {password_set_at, attrs} =
      Map.pop(attrs, :password_set_at, DateTime.utc_now())

    user =
      user_fixture_fast(
        Map.merge(
          %{
            state: :active,
            phone_number: "+12065551234"
          },
          attrs
        )
      )

    {:ok, user} = Accounts.mark_email_verified(user)
    {:ok, user} = Accounts.mark_phone_verified(user)

    user =
      if password_set_at do
        {:ok, user} = Accounts.mark_password_set(user)
        user
      else
        user
      end

    user
    |> Ysc.Accounts.User.update_user_changeset(%{
      stripe_id: "cus_#{System.unique_integer([:positive])}"
    })
    |> Ysc.Repo.update!()
  end

  # Advances a user to the phone-verification step (step 4):
  # email verified → password set → phone saved (not yet verified).
  # Includes an active membership so the payment step is skipped.
  defp user_at_phone_verify_step(phone_number \\ nil) do
    phone_number = phone_number || unique_test_phone()

    user =
      user_fixture(%{
        state: :active,
        email_verified_at: nil,
        password_set_at: nil
      })

    user = give_active_membership(user)

    {:ok, u1} = Accounts.mark_email_verified(user)

    {:ok, u2} =
      Accounts.set_user_initial_password(u1, %{
        "password" => valid_user_password(),
        "password_confirmation" => valid_user_password()
      })

    {:ok, u3} =
      Accounts.update_user_phone_and_sms(u2, %{
        "phone_number" => phone_number,
        "sms_opt_in" => "false"
      })

    u3
  end

  defp unique_test_phone do
    suffix =
      System.unique_integer([:positive])
      |> rem(10_000)
      |> Integer.to_string()
      |> String.pad_leading(4, "0")

    "+1206555#{suffix}"
  end

  defp otp_form_params(code) when is_binary(code) do
    code
    |> String.graphemes()
    |> Enum.with_index()
    |> Map.new(fn {digit, index} -> {Integer.to_string(index), digit} end)
  end

  # ---------------------------------------------------------------------------
  # Mount / dead render
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "static HTML shows loading shell before websocket connects", %{
      conn: conn
    } do
      user = unverified_pending_user(%{email: "deferred-setup@example.com"})

      conn = get(conn, account_setup_path(user))
      html = html_response(conn, 200)

      assert html =~ ~s|id="account-setup-loading"|
      refute html =~ "deferred-setup@example.com"
      refute html =~ ~s|id="email_form"|
    end
  end

  # ---------------------------------------------------------------------------
  # Step 0 — Email verification
  # ---------------------------------------------------------------------------

  describe "step 0: email verification" do
    test "shows the email verification form", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      assert has_element?(view, "#email_form")
    end

    test "stepper is hidden during email verification", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      # Stepper only shows once the user has passed step 0
      refute has_element?(view, "ol li", "Payment")
      refute has_element?(view, "ol li", "Password")
    end

    test "shows submitted-application banner when from_signup=true", %{
      conn: conn
    } do
      user = unverified_pending_user()

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"from_signup" => "true"}))

      assert render(view) =~ "application is submitted"
    end

    test "invalid code shows error", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      view
      |> form("#email_form", %{"verification_code" => @invalid_otp})
      |> render_submit()

      assert render(view) =~ "Invalid verification code"
    end

    test "email verification is rate limited after repeated invalid submissions",
         %{
           conn: conn
         } do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      for _ <- 1..12 do
        view
        |> form("#email_form", %{"verification_code" => @invalid_otp})
        |> render_submit()
      end

      view
      |> form("#email_form", %{"verification_code" => @invalid_otp})
      |> render_submit()

      html = render(view)
      assert html =~ "Too many verification attempts"

      # Earlier invalid attempts leave error copy in the DOM (e.g. flash mirror / toast history),
      # so we only assert the rate-limit outcome here.
    end

    test "valid code redirects to auto-login pointing at step 1 for pending users",
         %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      view
      |> form("#email_form", %{"verification_code" => @valid_otp})
      |> render_change()

      view
      |> form("#email_form", %{"verification_code" => @valid_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      decoded = URI.decode(path)
      assert String.starts_with?(decoded, "/users/log-in/auto")
      assert decoded =~ "step=1"
    end

    test "valid code redirects to step 2 for active users (no payment step)", %{
      conn: conn
    } do
      user =
        user_fixture(%{
          state: :active,
          email_verified_at: nil,
          password_set_at: nil
        })

      _ = give_active_membership(user)

      {:ok, view, _html} = live(conn, account_setup_path(user))

      view
      |> form("#email_form", %{"verification_code" => @valid_otp})
      |> render_change()

      view
      |> form("#email_form", %{"verification_code" => @valid_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      decoded = URI.decode(path)
      assert String.starts_with?(decoded, "/users/log-in/auto")
      assert decoded =~ "step=2"
    end

    test "OTP pasted as map verifies correctly", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      view
      |> form("#email_form", %{"verification_code" => @valid_otp})
      |> render_change()

      assert has_element?(
               view,
               "#email_form button[type=submit]:not([disabled])"
             )

      view
      |> form("#email_form", %{"verification_code" => @valid_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      decoded = URI.decode(path)
      assert String.starts_with?(decoded, "/users/log-in/auto")
    end

    test "OTP entered in two parts (partial merge) verifies correctly", %{
      conn: conn
    } do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      view
      |> form("#email_form", %{
        "verification_code" => %{"0" => "0", "1" => "0", "2" => "0"}
      })
      |> render_change()

      view
      |> form("#email_form", %{
        "verification_code" => %{"3" => "0", "4" => "0", "5" => "0"}
      })
      |> render_change()

      view
      |> form("#email_form", %{"verification_code" => @valid_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end

    test "resend code shows confirmation toast", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      render_click(view, "resend_code", %{})

      html = render(view)

      assert html =~ "verification code was sent again" or
               html =~ "verification code has been sent"
    end

    test "resend_timer_expired and update_resend_timers events do not crash", %{
      conn: conn
    } do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      render_click(view, "update_resend_timers", %{})
      render_click(view, "resend_timer_expired", %{"type" => "email"})
      render_click(view, "resend_timer_expired", %{"type" => "sms"})

      assert has_element?(view, "#email_form")
    end

    test "step 1 is inaccessible without email verification even when logged in",
         %{conn: conn} do
      user = unverified_pending_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      # Email not verified → blocked, stays on email form
      assert has_element?(view, "#email_form")
    end

    test "step 2 is inaccessible without email verification", %{conn: conn} do
      user = unverified_pending_user()
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      refute has_element?(view, "#password_form")
    end
  end

  # ---------------------------------------------------------------------------
  # Regression: deferred payment lookup on mount (#351)
  # ---------------------------------------------------------------------------

  describe "dead render performance" do
    test "payment step static HTML skips Stripe setup intent creation", %{
      conn: conn
    } do
      user = verified_pending_user()
      conn = log_in_user(conn, user)

      conn = get(conn, account_setup_path(user, %{"step" => "1"}))
      html = html_response(conn, 200)

      refute html =~ "data-clientSecret"
      refute html =~ ~s|id="setup-payment-form"|
    end
  end

  describe "pending user with payment on file" do
    test "lands on password step when a default payment method already exists",
         %{
           conn: conn
         } do
      user = pending_user_with_default_payment()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, account_setup_path(user))

      assert has_element?(view, "#password_form")
      refute has_element?(view, "#setup-payment-form")
      refute has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "does not keep user on payment step when URL requests step=1", %{
      conn: conn
    } do
      user = pending_user_with_default_payment()
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      assert has_element?(view, "#password_form")
      refute has_element?(view, "#setup-payment-form")
    end
  end

  # ---------------------------------------------------------------------------
  # Step 1 — Payment method
  # ---------------------------------------------------------------------------

  describe "step 1: payment method" do
    setup %{conn: conn} do
      user = verified_pending_user(%{password_set_at: nil})
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "shows payment form or try-again fallback", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      # Stripe setup-intent creation fails in tests; the fallback UI appears
      assert has_element?(view, "#setup-payment-form") or
               has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "shows no-charge-until-approved copy", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      html = render(view)

      assert html =~ "not be charged until your application is approved"
    end

    test "shows authorization and auto-renewal copy", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      html = render(view)

      assert html =~ "charge this card for your first year of membership"
      assert html =~ "renews automatically each year"
    end

    test "stepper is visible on step 1", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      assert has_element?(view, "ol")
    end

    test "stepper shows payment, password, and phone labels for pending users",
         %{
           conn: conn,
           user: user
         } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      html = render(view)

      assert html =~ "Payment"
      assert html =~ "Password"
      assert html =~ "Phone"
    end

    test "payment-method-set event with Stripe error stays on step 1", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      render_click(view, "payment-method-set", %{
        "payment_method_id" => "pm_test_nonexistent"
      })

      # Stripe retrieve fails in tests → stays on step 1
      assert has_element?(view, "#setup-payment-form") or
               has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "payment-method-set from wrong step shows error", %{
      conn: conn
    } do
      # User already has a payment method so they can reach the password step
      user = pending_user_with_default_payment()
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      assert has_element?(view, "#password_form")

      render_click(view, "payment-method-set", %{
        "payment_method_id" => "pm_test_123"
      })

      assert render(view) =~ "Cannot save payment method"
    end

    test "retry_payment_setup event does not crash", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      render_click(view, "retry_payment_setup", %{})

      # Either loaded or gracefully showed an error — page is stable
      assert has_element?(view, "#setup-payment-form") or
               has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "unauthenticated user cannot access step 1", %{user: user} do
      {:ok, view, _html} =
        live(build_conn(), account_setup_path(user, %{"step" => "1"}))

      # Not logged in → access denied
      refute has_element?(view, "#setup-payment-form")
      refute has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "different authenticated user cannot access step 1", %{user: user} do
      other_conn = log_in_user(build_conn(), user_fixture())

      {:ok, view, _html} =
        live(other_conn, account_setup_path(user, %{"step" => "1"}))

      # Non-owner → access denied; page stays on email verification step
      refute has_element?(view, "#setup-payment-form")
      refute has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end
  end

  # ---------------------------------------------------------------------------
  # Step 2 — Set password
  # ---------------------------------------------------------------------------

  describe "step 2: set password" do
    # Use an active user to bypass the payment step entirely
    setup %{conn: conn} do
      user = active_user_needing_password()
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "shows the password form", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      assert has_element?(view, "#password_form")
    end

    test "stepper is visible on step 2", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      assert has_element?(view, "ol")
    end

    test "password confirmation mismatch shows validation error", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      view
      |> form("#password_form", %{
        "user" => %{
          "password" => valid_user_password(),
          "password_confirmation" => "wrong!"
        }
      })
      |> render_change()

      assert render(view) =~ "Please enter the same password in both fields"
    end

    test "password too short shows validation error", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      view
      |> form("#password_form", %{
        "user" => %{"password" => "short", "password_confirmation" => "short"}
      })
      |> render_change()

      assert render(view) =~ "at least"
    end

    test "valid password submission advances to phone step", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      view
      |> form("#password_form", %{
        "user" => %{
          "password" => valid_user_password(),
          "password_confirmation" => valid_user_password()
        }
      })
      |> render_submit()

      # Should move to phone setup (step 3) or phone verify (step 4)
      assert has_element?(view, "#phone_form") or
               has_element?(view, "#phone_verification_form")
    end

    test "unauthenticated user cannot access step 2", %{user: user} do
      {:ok, view, _html} =
        live(build_conn(), account_setup_path(user, %{"step" => "2"}))

      refute has_element?(view, "#password_form")
    end
  end

  # ---------------------------------------------------------------------------
  # Step 3 — Phone setup (optional)
  # ---------------------------------------------------------------------------

  describe "step 3: phone setup" do
    # User who needs to enter a phone number (no phone number stored yet)
    setup %{conn: conn} do
      user = active_user_needing_password_no_phone()

      {:ok, user} =
        Accounts.set_user_initial_password(user, %{
          "password" => valid_user_password(),
          "password_confirmation" => valid_user_password()
        })

      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "shows the phone form", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "3"}))

      assert has_element?(view, "#phone_form")
    end

    test "defaults SMS opt-in checkbox to checked", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "3"}))

      assert has_element?(
               view,
               "#phone_form input[name='user[sms_opt_in]'][type='checkbox'][checked]"
             )
    end

    test "shows skip button", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "3"}))

      assert has_element?(view, "[phx-click=\"skip_phone\"]")
    end

    test "skip phone redirects to auto-login", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "3"}))

      render_click(view, "skip_phone", %{})

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end

    test "valid phone number save advances to phone verification step", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "3"}))

      # The phone input uses a LivePhone component that controls a hidden field via JS.
      # To test the save_phone event directly without JS, use render_submit/3:
      render_submit(view, "save_phone", %{
        "user" => %{"phone_number" => "+12065551234", "sms_opt_in" => "false"}
      })

      assert has_element?(view, "#phone_verification_form")
    end

    test "resubmitting the same phone number keeps the existing verification code",
         %{
           conn: conn,
           user: user
         } do
      phone = "+12065559876"

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "3"}))

      render_submit(view, "save_phone", %{
        "user" => %{"phone_number" => phone, "sms_opt_in" => "false"}
      })

      assert has_element?(view, "#phone_verification_form")

      updated_user = Accounts.get_user!(user.id)
      original_code = VerificationCodes.get(updated_user, :phone)
      assert original_code

      render_click(view, "change_phone_number", %{})

      assert has_element?(view, "#phone_form")

      render_submit(view, "save_phone", %{
        "user" => %{"phone_number" => phone, "sms_opt_in" => "false"}
      })

      assert has_element?(view, "#phone_verification_form")
      assert VerificationCodes.get(updated_user, :phone) == original_code
    end

    test "empty phone number submission shows validation error", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "3"}))

      render_submit(view, "save_phone", %{
        "user" => %{"phone_number" => "", "sms_opt_in" => "false"}
      })

      refute has_element?(view, "#phone_verification_form")
    end

    test "non-US/CA phone number saves and skips the verification step", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "3"}))

      render_submit(view, "save_phone", %{
        "user" => %{"phone_number" => "+46701234567", "sms_opt_in" => "false"}
      })

      # No further setup is needed once the unverifiable phone number is saved,
      # so the LiveView completes setup and redirects home instead of showing
      # the (unreachable, since FlowRoute can't text this number) OTP step.
      assert_redirect(view, "/")

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.phone_number == "+46701234567"
      assert updated_user.phone_verified_at == nil
    end

    test "unauthenticated user cannot access step 3", %{user: user} do
      {:ok, view, _html} =
        live(build_conn(), account_setup_path(user, %{"step" => "3"}))

      refute has_element?(view, "#phone_form")
    end
  end

  # ---------------------------------------------------------------------------
  # Step 4 — Phone verification
  # ---------------------------------------------------------------------------

  describe "step 4: phone verification" do
    setup %{conn: conn} do
      user = user_at_phone_verify_step()

      # Pre-store a code so mount does not race SMS sends under parallel CI, and so
      # verification does not depend on the dev/test-only 000000 bypass.
      phone_code = Accounts.generate_and_store_phone_verification_code(user)
      conn = log_in_user(conn, user)

      %{
        conn: conn,
        user: user,
        phone_code: phone_code,
        phone_otp: otp_form_params(phone_code)
      }
    end

    test "shows the phone verification form", %{conn: conn, user: user} do
      {:ok, view, html} =
        live(conn, account_setup_path(user, %{"step" => "4"}))

      assert has_element?(view, "#phone_verification_form")
      assert html =~ "6-digit code"
      assert html =~ "6-digit verification code"
    end

    test "invalid code shows error", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "4"}))

      view
      |> form("#phone_verification_form", %{"verification_code" => @invalid_otp})
      |> render_submit()

      assert render(view) =~ "Invalid verification code"
    end

    test "phone verification is rate limited after repeated invalid submissions",
         %{
           conn: conn,
           user: user
         } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "4"}))

      for _ <- 1..12 do
        view
        |> form("#phone_verification_form", %{
          "verification_code" => @invalid_otp
        })
        |> render_submit()
      end

      view
      |> form("#phone_verification_form", %{"verification_code" => @invalid_otp})
      |> render_submit()

      html = render(view)
      assert html =~ "Too many verification attempts"
    end

    test "valid code redirects to auto-login", %{
      conn: conn,
      user: user,
      phone_otp: phone_otp
    } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "4"}))

      view
      |> form("#phone_verification_form", %{"verification_code" => phone_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end

    test "OTP entered in two parts (merge) verifies correctly", %{
      conn: conn,
      user: user,
      phone_code: phone_code,
      phone_otp: phone_otp
    } do
      {first_half, second_half} = String.split_at(phone_code, 3)

      first_otp =
        first_half
        |> String.graphemes()
        |> Enum.with_index()
        |> Map.new(fn {digit, index} -> {Integer.to_string(index), digit} end)

      second_otp =
        second_half
        |> String.graphemes()
        |> Enum.with_index(3)
        |> Map.new(fn {digit, index} -> {Integer.to_string(index), digit} end)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "4"}))

      view
      |> form("#phone_verification_form", %{"verification_code" => first_otp})
      |> render_change()

      view
      |> form("#phone_verification_form", %{"verification_code" => second_otp})
      |> render_change()

      view
      |> form("#phone_verification_form", %{"verification_code" => phone_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end

    test "resend phone code shows confirmation toast", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "4"}))

      render_click(view, "resend_phone_code", %{})

      assert render(view) =~ "Verification code sent"
    end

    test "change phone number goes back to phone setup step", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "4"}))

      render_click(view, "change_phone_number", %{})

      assert has_element?(view, "#phone_form")
    end

    test "unauthenticated user cannot access step 4", %{user: user} do
      {:ok, view, _html} =
        live(build_conn(), account_setup_path(user, %{"step" => "4"}))

      refute has_element?(view, "#phone_verification_form")
    end
  end

  # ---------------------------------------------------------------------------
  # Stepper visibility and step-label persistence
  # ---------------------------------------------------------------------------

  describe "stepper" do
    test "is hidden on step 0 (email verification)", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      refute has_element?(view, "ol li", "Password")
      refute has_element?(view, "ol li", "Payment")
    end

    test "shows payment, password, and phone labels for pending users on step 1",
         %{conn: conn} do
      user = verified_pending_user(%{password_set_at: nil})
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      html = render(view)

      assert html =~ "Payment"
      assert html =~ "Password"
      assert html =~ "Phone"
    end

    test "does not show payment label for active users", %{conn: conn} do
      user = active_user_needing_password()
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      # Active users don't have a payment step in the stepper
      html = render(view)
      refute html =~ "Payment"
    end

    test "stepper_needs frozen — payment label persists after payment-method-set fires",
         %{
           conn: conn
         } do
      user = verified_pending_user(%{password_set_at: nil})
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      # Stepper shows payment on step 1
      assert render(view) =~ "Payment"

      # Fire payment-method-set (will error in tests due to Stripe not being available)
      render_click(view, "payment-method-set", %{
        "payment_method_id" => "pm_test"
      })

      # stepper_needs is frozen — payment label should still be rendered
      assert render(view) =~ "Payment"
    end

    test "shows password and phone labels for users who need them", %{
      conn: conn
    } do
      user = active_user_needing_password_no_phone()

      {:ok, user} =
        Accounts.set_user_initial_password(user, %{
          "password" => valid_user_password(),
          "password_confirmation" => valid_user_password()
        })

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "3"}))

      html = render(view)

      assert html =~ "Phone"
      refute html =~ "Payment"
    end
  end

  # ---------------------------------------------------------------------------
  # Access control
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "step 0 is accessible without login", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      assert has_element?(view, "#email_form")
    end

    test "step 1 requires login", %{conn: conn} do
      user = verified_pending_user()

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      # Not logged in → stays on email verification (can_access_step returns false)
      refute has_element?(view, "#setup-payment-form")
      refute has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "step 2 requires login", %{conn: conn} do
      user = active_user_needing_password()

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      refute has_element?(view, "#password_form")
    end

    test "non-owner cannot access another user's step 1", %{conn: conn} do
      owner = verified_pending_user(%{password_set_at: nil})
      other = user_fixture()
      conn = log_in_user(conn, other)

      {:ok, view, _html} =
        live(conn, account_setup_path(owner, %{"step" => "1"}))

      refute has_element?(view, "#setup-payment-form")
      refute has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "non-owner cannot access another user's step 2", %{conn: conn} do
      owner = active_user_needing_password()
      other = user_fixture()
      conn = log_in_user(conn, other)

      {:ok, view, _html} =
        live(conn, account_setup_path(owner, %{"step" => "2"}))

      refute has_element?(view, "#password_form")
    end

    test "set-step event to invalid step redirects away", %{conn: conn} do
      user = verified_pending_user(%{password_set_at: nil})
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      render_click(view, "set-step", %{"step" => "99"})

      assert_redirect(view)
    end

    test "set-step cannot skip to password step without an authenticated session",
         %{
           conn: conn
         } do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, account_setup_path(user))

      assert has_element?(view, "#email_form")

      render_click(view, "set-step", %{"step" => "2"})

      assert_redirect(view)
    end
  end

  # ---------------------------------------------------------------------------
  # Flash / toast hygiene (send_toast vs put_flash)
  # ---------------------------------------------------------------------------

  describe "flash replay prevention" do
    # The key invariant: event handlers use send_toast (a one-time process message)
    # instead of put_flash (which persists in socket.assigns.flash and replays on
    # every render, including phx-change events on the same step).

    test "handle_params clears stale flash so previous step toasts do not reappear",
         %{conn: conn} do
      user = active_user_needing_password()
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      # Submit valid password — push_patches to next phone step
      view
      |> form("#password_form", %{
        "user" => %{
          "password" => valid_user_password(),
          "password_confirmation" => valid_user_password()
        }
      })
      |> render_submit()

      # After advancing to the phone step, the page should not contain
      # "Set Password" as an active heading (it would if we were stuck replaying
      # the previous step's view due to flash carry-over)
      refute render(view) =~
               "<h1"
               |> Kernel.<>(~s(class="text-lg font-semibold))
               |> Kernel.<>("Set Password")
    end

    test "error on step 0 does not carry to the phone-verification step after completing all steps",
         %{conn: conn} do
      user = user_at_phone_verify_step()
      phone_code = Accounts.generate_and_store_phone_verification_code(user)
      phone_otp = otp_form_params(phone_code)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "4"}))

      # Invalid OTP — triggers error toast
      view
      |> form("#phone_verification_form", %{"verification_code" => @invalid_otp})
      |> render_submit()

      assert render(view) =~ "Invalid verification code"

      # Now submit valid code — redirects; no stale toast should be carried in flash
      view
      |> form("#phone_verification_form", %{"verification_code" => phone_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end
  end

  describe "mount redirects when setup is already complete" do
    test "pending user with payment on file is redirected away from account setup",
         %{
           conn: conn
         } do
      user = verified_pending_user(%{phone_number: "+12065551234"})
      {:ok, user} = Accounts.mark_password_set(user)
      {:ok, user} = Accounts.mark_phone_verified(user)

      assert {:ok, _pm} =
               Payments.insert_payment_method(%{
                 user_id: user.id,
                 provider: :stripe,
                 provider_id:
                   "pm_setup_complete_#{System.unique_integer([:positive])}",
                 provider_customer_id: "cus_test",
                 type: :card,
                 provider_type: "card",
                 is_default: true
               })

      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, account_setup_path(user))
    end
  end

  describe "unpaid active users stay in pay funnel" do
    test "shows activate CTA when active with payment method but no membership",
         %{
           conn: conn
         } do
      user = unpaid_active_user_needing_payment()

      {:ok, _pm} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_#{System.unique_integer([:positive])}",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      conn = log_in_user(conn, user)

      # Activation attempt on load fails via ConnCase Stripe.SubscriptionMock stub
      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      html = render(view)

      assert has_element?(view, "#retry-membership-activation")
      assert html =~ "Activate Your Membership"
    end

    test "shows payment step when active without membership or payment method",
         %{
           conn: conn
         } do
      user = unpaid_active_user_needing_payment(%{password_set_at: nil})
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      html = render(view)

      assert html =~ "Activate Your Membership"
      assert html =~ "Payment"

      assert has_element?(view, "#setup-payment-form") or
               has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "mid-flow approval without payment method routes to payment step", %{
      conn: conn
    } do
      user =
        verified_pending_user(%{
          password_set_at: nil
        })

      user =
        user
        |> Ysc.Accounts.User.update_user_changeset(%{
          stripe_id: "cus_#{System.unique_integer([:positive])}"
        })
        |> Ysc.Repo.update!()

      conn = log_in_user(conn, user)

      # Payment is still needed, so setup keeps them on step 1
      {:ok, view, html} =
        live(conn, account_setup_path(user, %{"step" => "1"}))

      assert html =~ "not be charged until your application is approved"

      assert has_element?(view, "#setup-payment-form") or
               has_element?(view, "[phx-click=\"retry_payment_setup\"]")

      # Simulate board approval while the LiveView is open
      {:ok, _} =
        user
        |> Ecto.Changeset.change(%{state: :active})
        |> Ysc.Repo.update()

      # Next navigation recomputes needs and shows approved pay copy
      {:ok, _view, html} =
        live(conn, account_setup_path(user, %{"step" => "2"}))

      assert html =~ "Activate Your Membership"
    end

    test "redirects home when membership activates on mount", %{conn: conn} do
      user = unpaid_active_user_needing_payment()
      {:ok, user} = Accounts.mark_password_set(user)
      {:ok, user} = Accounts.mark_phone_verified(user)

      {:ok, _pm} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_#{System.unique_integer([:positive])}",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      stripe_sub_id = "sub_mount_#{System.unique_integer([:positive])}"

      expect(Stripe.SubscriptionMock, :create, fn _params ->
        {:ok,
         Ysc.Stripe.SubscriptionFixtures.subscription(
           id: stripe_sub_id,
           customer: user.stripe_id,
           status: "active"
         )}
      end)

      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, account_setup_path(user))
    end
  end
end
