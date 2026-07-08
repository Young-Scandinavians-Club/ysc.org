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
          city: "Stockholm",
          threat_indicators: ["new_device"]
        })
        |> Repo.insert()

      {:ok, assigns} = NewSignInDetected.prepare_email_data(user, auth_event.id)

      assert assigns.first_name == Ysc.title_case(user.first_name)
      assert assigns.device == "Chrome on macOS"
      assert assigns.location == "Stockholm, Stockholm, SE (24.206.103.29)"
      assert assigns.security_url =~ "/users/settings/security"
      assert is_binary(assigns.signed_in_at)

      assert assigns.intro_text ==
               "We noticed a sign-in to Young Scandinavians Club from a new device or browser."
    end

    test "falls back to IP when geo has not been resolved yet" do
      user = user_fixture()

      {:ok, auth_event} =
        AuthEvent.login_success_changeset(user, %{
          ip_address: "203.0.113.1",
          browser: "Chrome",
          operating_system: "macOS",
          threat_indicators: ["unusual_location"]
        })
        |> Repo.insert()

      {:ok, assigns} = NewSignInDetected.prepare_email_data(user, auth_event.id)

      assert assigns.location == "203.0.113.1"

      assert assigns.intro_text ==
               "We noticed a sign-in to Young Scandinavians Club from a new location."
    end

    test "returns error when auth event is missing" do
      user = user_fixture()

      assert {:error, :auth_event_not_found} =
               NewSignInDetected.prepare_email_data(user, Ecto.ULID.generate())
    end
  end

  describe "text_body/1" do
    test "includes intro and sign-in details" do
      body =
        NewSignInDetected.text_body(%{
          first_name: "Ada",
          intro_text:
            "We noticed a sign-in to Young Scandinavians Club from a new location.",
          signed_in_at: "Jan 1, 2026 at 9:00 AM PST",
          device: "Chrome on macOS",
          location: "Stockholm, Stockholm, SE (24.206.103.29)",
          security_url: "https://example.com/users/settings/security"
        })

      assert body =~ "Hi Ada,"
      assert body =~ "new location"
      assert body =~ "Platform: Chrome on macOS"
      assert body =~ "Location: Stockholm, Stockholm, SE (24.206.103.29)"
      assert body =~ "Time: Jan 1, 2026 at 9:00 AM PST"
      assert body =~ "https://example.com/users/settings/security"
    end
  end
end
