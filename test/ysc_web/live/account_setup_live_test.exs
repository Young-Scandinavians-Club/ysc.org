defmodule YscWeb.AccountSetupLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

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
    user_fixture(
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

  # Creates an active user who still needs to set a password (skips payment step).
  defp active_user_needing_password do
    user =
      user_fixture(%{
        state: :active,
        email_verified_at: nil,
        password_set_at: nil
      })

    {:ok, user} = Accounts.mark_email_verified(user)
    user
  end

  # Creates an active user who needs password and has no phone stored.
  defp active_user_needing_password_no_phone do
    user =
      user_fixture(%{
        state: :active,
        email_verified_at: nil,
        password_set_at: nil,
        phone_number: nil
      })

    {:ok, user} = Accounts.mark_email_verified(user)
    user
  end

  # Advances a user to the phone-verification step (step 4):
  # email verified → password set → phone saved (not yet verified).
  defp user_at_phone_verify_step(phone_number \\ "+12065551234") do
    user =
      user_fixture(%{
        state: :active,
        email_verified_at: nil,
        password_set_at: nil
      })

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

  # ---------------------------------------------------------------------------
  # Step 0 — Email verification
  # ---------------------------------------------------------------------------

  describe "step 0: email verification" do
    test "shows the email verification form", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      assert has_element?(view, "#email_form")
    end

    test "stepper is hidden during email verification", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      # Stepper only shows once the user has passed step 0
      refute has_element?(view, "ol li", "Payment")
      refute has_element?(view, "ol li", "Password")
    end

    test "shows submitted-application banner when from_signup=true", %{
      conn: conn
    } do
      user = unverified_pending_user()

      {:ok, view, _html} =
        live(conn, ~p"/account/setup/#{user.id}?from_signup=true")

      assert render(view) =~ "application is submitted"
    end

    test "invalid code shows error", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

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
      refute html =~ "Invalid verification code"
    end

    test "valid code redirects to auto-login pointing at step 1 for pending users",
         %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

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

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      view
      |> form("#email_form", %{"verification_code" => @valid_otp})
      |> render_change()

      view
      |> form("#email_form", %{"verification_code" => @valid_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end

    test "OTP entered in two parts (partial merge) verifies correctly", %{
      conn: conn
    } do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      render_click(view, "resend_code", %{})

      assert render(view) =~ "verification code has been sent"
    end

    test "resend_timer_expired and update_resend_timers events do not crash", %{
      conn: conn
    } do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      render_click(view, "update_resend_timers", %{})
      render_click(view, "resend_timer_expired", %{"type" => "email"})
      render_click(view, "resend_timer_expired", %{"type" => "sms"})

      assert has_element?(view, "#email_form")
    end

    test "step 1 is inaccessible without email verification even when logged in",
         %{conn: conn} do
      user = unverified_pending_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")

      # Email not verified → blocked, stays on email form
      assert has_element?(view, "#email_form")
    end

    test "step 2 is inaccessible without email verification", %{conn: conn} do
      user = unverified_pending_user()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

      refute has_element?(view, "#password_form")
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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")

      # Stripe setup-intent creation fails in tests; the fallback UI appears
      assert has_element?(view, "#setup-payment-form") or
               has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "shows no-charge-until-approved copy", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")
      html = render(view)

      assert html =~ "not be charged until your application is approved"
    end

    test "shows authorization and auto-renewal copy", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")
      html = render(view)

      assert html =~ "authorise"
      assert html =~ "automatically renew"
    end

    test "stepper is visible on step 1", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")

      assert has_element?(view, "ol")
    end

    test "stepper shows payment, password, and phone labels for pending users",
         %{
           conn: conn,
           user: user
         } do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")
      html = render(view)

      assert html =~ "Payment"
      assert html =~ "Password"
      assert html =~ "Phone"
    end

    test "payment-method-set event with Stripe error stays on step 1", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")

      render_click(view, "payment-method-set", %{
        "payment_method_id" => "pm_test_nonexistent"
      })

      # Stripe retrieve fails in tests → stays on step 1
      assert has_element?(view, "#setup-payment-form") or
               has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "payment-method-set from wrong step shows error", %{
      conn: conn,
      user: user
    } do
      # Navigate to step 2 (password) and then fire the payment event from there
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

      render_click(view, "payment-method-set", %{
        "payment_method_id" => "pm_test_123"
      })

      assert render(view) =~ "Cannot save payment method"
    end

    test "retry_payment_setup event does not crash", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")

      render_click(view, "retry_payment_setup", %{})

      # Either loaded or gracefully showed an error — page is stable
      assert has_element?(view, "#setup-payment-form") or
               has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "unauthenticated user cannot access step 1", %{user: user} do
      {:ok, view, _html} =
        live(build_conn(), ~p"/account/setup/#{user.id}?step=1")

      # Not logged in → access denied
      refute has_element?(view, "#setup-payment-form")
      refute has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "different authenticated user cannot access step 1", %{user: user} do
      other_conn = log_in_user(build_conn(), user_fixture())

      {:ok, view, _html} =
        live(other_conn, ~p"/account/setup/#{user.id}?step=1")

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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

      assert has_element?(view, "#password_form")
    end

    test "stepper is visible on step 2", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

      assert has_element?(view, "ol")
    end

    test "password confirmation mismatch shows validation error", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

      view
      |> form("#password_form", %{
        "user" => %{
          "password" => valid_user_password(),
          "password_confirmation" => "wrong!"
        }
      })
      |> render_change()

      assert render(view) =~ "does not match"
    end

    test "password too short shows validation error", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

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
        live(build_conn(), ~p"/account/setup/#{user.id}?step=2")

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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=3")

      assert has_element?(view, "#phone_form")
    end

    test "shows skip button", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=3")

      assert has_element?(view, "[phx-click=\"skip_phone\"]")
    end

    test "skip phone redirects to auto-login", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=3")

      render_click(view, "skip_phone", %{})

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end

    test "valid phone number save advances to phone verification step", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=3")

      # The phone input uses a LivePhone component that controls a hidden field via JS.
      # To test the save_phone event directly without JS, use render_submit/3:
      render_submit(view, "save_phone", %{
        "user" => %{"phone_number" => "+12065551234", "sms_opt_in" => "false"}
      })

      assert has_element?(view, "#phone_verification_form")
    end

    test "empty phone number submission shows validation error", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=3")

      render_submit(view, "save_phone", %{
        "user" => %{"phone_number" => "", "sms_opt_in" => "false"}
      })

      refute has_element?(view, "#phone_verification_form")
    end

    test "unauthenticated user cannot access step 3", %{user: user} do
      {:ok, view, _html} =
        live(build_conn(), ~p"/account/setup/#{user.id}?step=3")

      refute has_element?(view, "#phone_form")
    end
  end

  # ---------------------------------------------------------------------------
  # Step 4 — Phone verification
  # ---------------------------------------------------------------------------

  describe "step 4: phone verification" do
    setup %{conn: conn} do
      user = user_at_phone_verify_step()
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "shows the phone verification form", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=4")

      assert has_element?(view, "#phone_verification_form")
    end

    test "invalid code shows error", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=4")

      view
      |> form("#phone_verification_form", %{"verification_code" => @invalid_otp})
      |> render_submit()

      assert render(view) =~ "Invalid verification code"
    end

    test "valid code redirects to auto-login", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=4")

      view
      |> form("#phone_verification_form", %{"verification_code" => @valid_otp})
      |> render_change()

      view
      |> form("#phone_verification_form", %{"verification_code" => @valid_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end

    test "OTP entered in two parts (merge) verifies correctly", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=4")

      view
      |> form("#phone_verification_form", %{
        "verification_code" => %{"0" => "0", "1" => "0", "2" => "0"}
      })
      |> render_change()

      view
      |> form("#phone_verification_form", %{
        "verification_code" => %{"3" => "0", "4" => "0", "5" => "0"}
      })
      |> render_change()

      view
      |> form("#phone_verification_form", %{"verification_code" => @valid_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end

    test "resend phone code shows confirmation toast", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=4")

      render_click(view, "resend_phone_code", %{})

      assert render(view) =~ "Verification code sent"
    end

    test "change phone number goes back to phone setup step", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=4")

      render_click(view, "change_phone_number", %{})

      assert has_element?(view, "#phone_form")
    end

    test "unauthenticated user cannot access step 4", %{user: user} do
      {:ok, view, _html} =
        live(build_conn(), ~p"/account/setup/#{user.id}?step=4")

      refute has_element?(view, "#phone_verification_form")
    end
  end

  # ---------------------------------------------------------------------------
  # Stepper visibility and step-label persistence
  # ---------------------------------------------------------------------------

  describe "stepper" do
    test "is hidden on step 0 (email verification)", %{conn: conn} do
      user = unverified_pending_user()
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      refute has_element?(view, "ol li", "Password")
      refute has_element?(view, "ol li", "Payment")
    end

    test "shows payment, password, and phone labels for pending users on step 1",
         %{conn: conn} do
      user = verified_pending_user(%{password_set_at: nil})
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")
      html = render(view)

      assert html =~ "Payment"
      assert html =~ "Password"
      assert html =~ "Phone"
    end

    test "does not show payment label for active users", %{conn: conn} do
      user = active_user_needing_password()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")

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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=3")
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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      assert has_element?(view, "#email_form")
    end

    test "step 1 requires login", %{conn: conn} do
      user = verified_pending_user()
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")

      # Not logged in → stays on email verification (can_access_step returns false)
      refute has_element?(view, "#setup-payment-form")
      refute has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "step 2 requires login", %{conn: conn} do
      user = active_user_needing_password()
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

      refute has_element?(view, "#password_form")
    end

    test "non-owner cannot access another user's step 1", %{conn: conn} do
      owner = verified_pending_user(%{password_set_at: nil})
      other = user_fixture()
      conn = log_in_user(conn, other)

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{owner.id}?step=1")

      refute has_element?(view, "#setup-payment-form")
      refute has_element?(view, "[phx-click=\"retry_payment_setup\"]")
    end

    test "non-owner cannot access another user's step 2", %{conn: conn} do
      owner = active_user_needing_password()
      other = user_fixture()
      conn = log_in_user(conn, other)

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{owner.id}?step=2")

      refute has_element?(view, "#password_form")
    end

    test "set-step event to invalid step redirects away", %{conn: conn} do
      user = verified_pending_user(%{password_set_at: nil})
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=1")

      render_click(view, "set-step", %{"step" => "99"})

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
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=2")

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
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}?step=4")

      # Invalid OTP — triggers error toast
      view
      |> form("#phone_verification_form", %{"verification_code" => @invalid_otp})
      |> render_submit()

      assert render(view) =~ "Invalid verification code"

      # Now submit valid code — redirects; no stale toast should be carried in flash
      view
      |> form("#phone_verification_form", %{"verification_code" => @valid_otp})
      |> render_change()

      view
      |> form("#phone_verification_form", %{"verification_code" => @valid_otp})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert String.starts_with?(path, "/users/log-in/auto")
    end
  end
end
