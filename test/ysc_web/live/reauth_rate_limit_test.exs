defmodule YscWeb.ReauthRateLimitTest do
  @moduledoc """
  Finding 89: step-up password reauth must share login's per-identifier
  AuthRateLimit cap so a stolen session cannot online-guess the password.
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias YscWeb.ReauthComponent

  setup do
    token =
      Ysc.Test.AuthRateLimitHelper.capture!(
        ip_limit: 10_000,
        identifier_limit: 2
      )

    on_exit(fn -> Ysc.Test.AuthRateLimitHelper.restore!(token) end)
    :ok
  end

  describe "Finding 89: ReauthComponent password step-up is rate limited" do
    test "blocks further guesses after the identifier limit" do
      user = user_fixture()
      socket = reauth_socket(user)

      {:noreply, first} =
        ReauthComponent.handle_event(
          "reauth_with_password",
          %{"password" => "wrong-password"},
          socket
        )

      assert first.assigns.reauth_error =~ "Invalid password"

      {:noreply, second} =
        ReauthComponent.handle_event(
          "reauth_with_password",
          %{"password" => "wrong-password"},
          first
        )

      assert second.assigns.reauth_error =~ "Invalid password"

      {:noreply, third} =
        ReauthComponent.handle_event(
          "reauth_with_password",
          %{"password" => valid_user_password()},
          second
        )

      assert third.assigns.reauth_error =~ "Too many attempts"
      refute_received :reauth_verified
    end
  end

  describe "Finding 89: settings email-change reauth is rate limited" do
    test "shows too-many-attempts after repeated invalid passwords", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => "reauth-limit@example.com"}
      })

      assert has_element?(view, "#reauth-modal")

      view
      |> element("#reauth_password_form")
      |> render_submit(%{"password" => "wrongpassword"})

      view
      |> element("#reauth_password_form")
      |> render_submit(%{"password" => "wrongpassword"})

      html =
        view
        |> element("#reauth_password_form")
        |> render_submit(%{"password" => valid_user_password()})

      assert html =~ "Too many attempts"
      assert has_element?(view, "#reauth-modal")
    end
  end

  defp reauth_socket(user) do
    assigns = %{
      __changed__: %{},
      user: user,
      user_has_password: true,
      description: "Please verify it's you",
      return_to: "/users/settings",
      reauth_intent: nil,
      reauth_error: nil,
      reauth_challenge: nil
    }

    %Phoenix.LiveView.Socket{assigns: assigns}
  end
end
