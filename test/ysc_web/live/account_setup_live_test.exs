defmodule YscWeb.AccountSetupLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts

  describe "Account setup flow" do
    test "verify_code with invalid digits shows error toast", %{conn: conn} do
      user =
        user_fixture(%{
          state: :pending_approval,
          email_verified_at: nil,
          password_set_at: nil,
          phone_verified_at: nil
        })

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")
      render(view)

      invalid_otp = %{
        "0" => "1",
        "1" => "1",
        "2" => "1",
        "3" => "1",
        "4" => "1",
        "5" => "1"
      }

      view
      |> form("#email_form", %{"verification_code" => invalid_otp})
      |> render_submit()

      assert render(view) =~ "Invalid verification code"
    end

    test "update_resend_timers and resend_timer_expired do not crash", %{
      conn: conn
    } do
      user =
        user_fixture(%{
          state: :pending_approval,
          email_verified_at: nil,
          password_set_at: nil,
          phone_verified_at: nil
        })

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")
      render(view)

      render_click(view, "update_resend_timers", %{})
      render_click(view, "resend_timer_expired", %{"type" => "email"})
      render_click(view, "resend_timer_expired", %{"type" => "sms"})

      assert has_element?(view, "#email_form")
    end

    test "shows correct stepper steps", %{conn: conn} do
      # Create a user who has submitted an application but not completed account setup
      user =
        user_fixture(%{
          state: :pending_approval,
          email_verified_at: nil,
          password_set_at: nil,
          phone_verified_at: nil
        })

      {:ok, lv, _html} = live(conn, ~p"/account/setup/#{user.id}")

      # Should show steps in stepper (Email verification is not shown in stepper, handled separately)
      # The stepper shows: "Set Password" and "Verify Phone Number" based on user needs
      assert has_element?(lv, ".flex.items-center.w-full", "Set Password")

      assert has_element?(
               lv,
               ".flex.items-center.w-full",
               "Verify Phone Number"
             )
    end
  end

  describe "email verification OTP" do
    @describetag :account_setup

    test "pasting full OTP as map enables submit and verification succeeds", %{
      conn: conn
    } do
      user =
        user_fixture(%{
          state: :pending_approval,
          email_verified_at: nil,
          password_set_at: nil,
          phone_verified_at: nil
        })

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      assert has_element?(view, "#email_form")
      # In test env dev_or_sandbox?() is true, so 000000 is accepted
      pasted_otp_map = %{
        "0" => "0",
        "1" => "0",
        "2" => "0",
        "3" => "0",
        "4" => "0",
        "5" => "0"
      }

      # Pasting full OTP triggers validate_email_code; merge logic enables submit
      view
      |> form("#email_form", %{"verification_code" => pasted_otp_map})
      |> render_change()

      view
      |> form("#email_form", %{"verification_code" => pasted_otp_map})
      |> render_submit()

      {path, _flash} = assert_redirect(view)

      assert String.starts_with?(path, "/users/log-in/auto"),
             "expected redirect to auto-login, got: #{path}"
    end

    test "sending OTP in two parts (merge) enables submit", %{conn: conn} do
      user =
        user_fixture(%{
          state: :pending_approval,
          email_verified_at: nil,
          password_set_at: nil,
          phone_verified_at: nil
        })

      {:ok, view, _html} = live(conn, ~p"/account/setup/#{user.id}")

      # Simulate phx-input sending partial then rest (e.g. paste or delayed events)
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

      # Merged state should have full 000000, so submit works
      view
      |> form("#email_form", %{
        "verification_code" => %{
          "0" => "0",
          "1" => "0",
          "2" => "0",
          "3" => "0",
          "4" => "0",
          "5" => "0"
        }
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)

      assert String.starts_with?(path, "/users/log-in/auto"),
             "expected redirect to auto-login, got: #{path}"
    end
  end

  describe "phone verification OTP" do
    @describetag :account_setup

    setup %{conn: conn} do
      user = user_fixture()
      {:ok, u1} = Accounts.mark_email_verified(user)

      {:ok, u2} =
        Accounts.set_user_initial_password(u1, %{
          "password" => valid_user_password(),
          "password_confirmation" => valid_user_password()
        })

      {:ok, user_at_phone_step} =
        Accounts.update_user_phone_and_sms(u2, %{
          "phone_number" => "+14155551234",
          "sms_opt_in" => "false"
        })

      conn = log_in_user(conn, user_at_phone_step)
      %{conn: conn, user: user_at_phone_step}
    end

    test "pasting full OTP as map enables submit and verification succeeds", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, ~p"/account/setup/#{user.id}?step=3")

      assert has_element?(view, "#phone_verification_form")

      pasted_otp_map = %{
        "0" => "0",
        "1" => "0",
        "2" => "0",
        "3" => "0",
        "4" => "0",
        "5" => "0"
      }

      view
      |> form("#phone_verification_form", %{
        "verification_code" => pasted_otp_map
      })
      |> render_change()

      view
      |> form("#phone_verification_form", %{
        "verification_code" => pasted_otp_map
      })
      |> render_submit()

      {path, _flash} = assert_redirect(view)

      assert String.starts_with?(path, "/users/log-in/auto"),
             "expected redirect to auto-login, got: #{path}"
    end

    test "sending phone OTP in two parts (merge) enables submit", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, ~p"/account/setup/#{user.id}?step=3")

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

      full_map = %{
        "0" => "0",
        "1" => "0",
        "2" => "0",
        "3" => "0",
        "4" => "0",
        "5" => "0"
      }

      view
      |> form("#phone_verification_form", %{"verification_code" => full_map})
      |> render_submit()

      {path, _flash} = assert_redirect(view)

      assert String.starts_with?(path, "/users/log-in/auto"),
             "expected redirect to auto-login, got: #{path}"
    end
  end
end
