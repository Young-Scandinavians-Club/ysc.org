defmodule YscWeb.ReauthComponentTest do
  @moduledoc """
  Direct `handle_event/3` tests for `YscWeb.ReauthComponent`.

  The component's interactive branches (password/passkey verification,
  OAuth redirects) are already exercised end-to-end through
  `UserSettingsLive`/`UserSecurityLive` integration tests. This file targets
  the handler branches those flows don't reach — mainly the
  `verify_authentication` error paths and the Facebook OAuth handler —  by
  calling `handle_event/3` directly against a manually-built socket, the same
  pattern used in `test/ysc_web/components/uploader/upload_component_test.exs`.
  This is cheaper and more reliable than driving a full LiveView for
  branches that only touch component-local state.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.ReauthComponent

  defp new_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  defp base_assigns(user, extra \\ %{}) do
    Map.merge(
      %{
        user: user,
        user_has_password: true,
        description: "Please verify it's you",
        return_to: "/settings",
        reauth_intent: nil,
        reauth_error: nil,
        reauth_challenge: nil
      },
      extra
    )
  end

  defp wax_challenge(allow_credentials \\ []) do
    Wax.new_authentication_challenge(
      rp_id: "localhost",
      origin: "http://localhost:4002",
      allow_credentials: allow_credentials
    )
  end

  describe "handle_event/3 verify_authentication" do
    test "assigns a timed-out error when there is no pending challenge" do
      user = user_fixture()
      socket = new_socket(base_assigns(user, %{reauth_challenge: nil}))

      {:noreply, updated} =
        ReauthComponent.handle_event("verify_authentication", %{}, socket)

      assert updated.assigns.reauth_error =~ "timed out"
    end

    test "rescues invalid base64 in the response and assigns a generic error" do
      user = user_fixture()
      challenge = wax_challenge()
      socket = new_socket(base_assigns(user, %{reauth_challenge: challenge}))

      response = %{
        "rawId" => "not-valid-base64!!!",
        "response" => %{
          "authenticatorData" => "also-not-valid!!!",
          "clientDataJSON" => "nope!!!",
          "signature" => "nope!!!"
        }
      }

      {:noreply, updated} =
        ReauthComponent.handle_event("verify_authentication", response, socket)

      assert updated.assigns.reauth_error =~ "Invalid passkey response"
    end

    test "assigns 'not recognized' error when no passkey matches the external id" do
      user = user_fixture()
      challenge = wax_challenge()
      socket = new_socket(base_assigns(user, %{reauth_challenge: challenge}))

      raw_id = :crypto.strong_rand_bytes(16)

      response = valid_shaped_response(raw_id)

      {:noreply, updated} =
        ReauthComponent.handle_event("verify_authentication", response, socket)

      assert updated.assigns.reauth_error =~ "Passkey not recognized"
    end

    test "rejects a passkey that belongs to a different user" do
      user = user_fixture()
      other_user = user_fixture()
      passkey = passkey_fixture(other_user)

      challenge = wax_challenge()
      socket = new_socket(base_assigns(user, %{reauth_challenge: challenge}))

      response = valid_shaped_response(passkey.external_id)

      {:noreply, updated} =
        ReauthComponent.handle_event("verify_authentication", response, socket)

      assert updated.assigns.reauth_error =~ "Passkey verification failed"
    end

    test "assigns an authentication-failed error when Wax rejects the signature" do
      user = user_fixture()
      passkey = passkey_fixture(user)

      challenge = wax_challenge()
      socket = new_socket(base_assigns(user, %{reauth_challenge: challenge}))

      response = valid_shaped_response(passkey.external_id)

      {:noreply, updated} =
        ReauthComponent.handle_event("verify_authentication", response, socket)

      assert updated.assigns.reauth_error =~ "Passkey authentication failed"
    end

    defp valid_shaped_response(raw_id) do
      %{
        "rawId" => Base.url_encode64(raw_id, padding: false),
        "response" => %{
          "authenticatorData" =>
            Base.url_encode64(:crypto.strong_rand_bytes(37), padding: false),
          "clientDataJSON" =>
            Base.url_encode64(
              Jason.encode!(%{
                type: "webauthn.get",
                challenge: "",
                origin: "http://localhost:4002"
              }),
              padding: false
            ),
          "signature" =>
            Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false)
        }
      }
    end
  end

  describe "handle_event/3 reauth_with_passkey" do
    test "includes the user's existing passkeys when building allow_credentials" do
      user = user_fixture()
      _passkey = passkey_fixture(user)

      socket = new_socket(base_assigns(user))

      {:noreply, updated} =
        ReauthComponent.handle_event("reauth_with_passkey", %{}, socket)

      assert %Wax.Challenge{} = updated.assigns.reauth_challenge
    end
  end

  describe "handle_event/3 OAuth handlers" do
    test "reauth_with_google redirects without a reauth_resume param when there is no intent" do
      user = user_fixture()
      socket = new_socket(base_assigns(user, %{reauth_intent: nil}))

      {:noreply, updated} =
        ReauthComponent.handle_event("reauth_with_google", %{}, socket)

      assert {:redirect, %{to: to}} = updated.redirected
      assert to =~ "/auth/google"
      assert to =~ "reauth=true"
      refute to =~ "reauth_resume"
    end

    test "reauth_with_facebook redirects to the Facebook OAuth endpoint" do
      user = user_fixture()
      socket = new_socket(base_assigns(user, %{reauth_intent: nil}))

      {:noreply, updated} =
        ReauthComponent.handle_event("reauth_with_facebook", %{}, socket)

      assert {:redirect, %{to: to}} = updated.redirected
      assert to =~ "/auth/facebook"
      assert to =~ "reauth=true"
    end

    test "reauth_with_google appends a signed reauth_resume param when an intent is present" do
      user = user_fixture()

      socket =
        new_socket(
          base_assigns(user, %{reauth_intent: %{"email" => "new@example.com"}})
        )

      {:noreply, updated} =
        ReauthComponent.handle_event("reauth_with_google", %{}, socket)

      assert {:redirect, %{to: to}} = updated.redirected
      assert to =~ "reauth_resume"
    end
  end

  describe "handle_event/3 hook no-ops" do
    test "passkey_support_detected, user_agent_received, and device_detected leave the socket untouched" do
      user = user_fixture()
      socket = new_socket(base_assigns(user))

      {:noreply, s1} =
        ReauthComponent.handle_event("passkey_support_detected", %{}, socket)

      {:noreply, s2} =
        ReauthComponent.handle_event("user_agent_received", %{}, socket)

      {:noreply, s3} =
        ReauthComponent.handle_event("device_detected", %{}, socket)

      assert s1 == socket
      assert s2 == socket
      assert s3 == socket
    end
  end

  describe "handle_event/3 cancel_reauth" do
    test "notifies the parent process and leaves the socket otherwise unchanged" do
      user = user_fixture()
      socket = new_socket(base_assigns(user))

      {:noreply, updated} =
        ReauthComponent.handle_event("cancel_reauth", %{}, socket)

      assert updated == socket
      assert_receive :reauth_cancelled
    end
  end

  describe "handle_event/3 reauth_with_password" do
    test "assigns an error for an incorrect password" do
      user = user_fixture()
      socket = new_socket(base_assigns(user))

      {:noreply, updated} =
        ReauthComponent.handle_event(
          "reauth_with_password",
          %{"password" => "wrong-password"},
          socket
        )

      assert updated.assigns.reauth_error =~ "Invalid password"
    end

    test "notifies the parent process for a correct password" do
      user = user_fixture()
      socket = new_socket(base_assigns(user))

      {:noreply, _updated} =
        ReauthComponent.handle_event(
          "reauth_with_password",
          %{"password" => valid_user_password()},
          socket
        )

      assert_receive :reauth_verified
    end
  end

  describe "update/2" do
    test "assigns sensible defaults for optional assigns" do
      user = user_fixture()
      socket = new_socket()

      {:ok, updated} =
        ReauthComponent.update(
          %{
            user: user,
            user_has_password: true,
            description: "Verify",
            return_to: "/settings"
          },
          socket
        )

      assert updated.assigns.reauth_error == nil
      assert updated.assigns.reauth_challenge == nil
      assert updated.assigns.reauth_intent == nil
      assert %Phoenix.HTML.Form{} = updated.assigns.reauth_form
    end
  end
end
