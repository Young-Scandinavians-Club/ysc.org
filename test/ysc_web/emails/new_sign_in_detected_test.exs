defmodule YscWeb.Emails.NewSignInDetectedTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Accounts.AuthEvent
  alias Ysc.Repo
  alias YscWeb.Emails.NewSignInDetected

  describe "prepare_email_data/2" do
    test "uses geo fields already persisted on the auth event" do
      user = user_fixture()

      {:ok, auth_event} =
        AuthEvent.login_success_changeset(user, %{
          ip_address: "24.206.103.29",
          browser: "Chrome",
          operating_system: "macOS",
          country: "SE",
          region: "Stockholm",
          city: "Stockholm"
        })
        |> Repo.insert()

      assigns = NewSignInDetected.prepare_email_data(user, auth_event.id)

      assert assigns.first_name == String.capitalize(user.first_name)
      assert assigns.device == "Chrome on macOS"
      assert assigns.location == "Stockholm, Stockholm, SE (24.206.103.29)"
      assert assigns.security_url =~ "/users/settings/security"
      assert is_binary(assigns.signed_in_at)
    end

    test "falls back to IP when geo has not been resolved yet" do
      user = user_fixture()

      {:ok, auth_event} =
        AuthEvent.login_success_changeset(user, %{
          ip_address: "203.0.113.1",
          browser: "Chrome",
          operating_system: "macOS"
        })
        |> Repo.insert()

      assigns = NewSignInDetected.prepare_email_data(user, auth_event.id)

      assert assigns.location == "203.0.113.1"
    end
  end
end
