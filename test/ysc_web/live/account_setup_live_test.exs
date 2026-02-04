defmodule YscWeb.AccountSetupLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  describe "Account setup flow" do
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
end
