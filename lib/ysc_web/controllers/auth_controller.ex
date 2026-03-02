defmodule YscWeb.AuthController do
  @moduledoc """
  Controller for handling OAuth authentication flows.
  """
  use YscWeb, :controller

  plug Ueberauth

  alias Ysc.Accounts
  alias YscWeb.UserAuth

  @doc """
  Handles OAuth request phase - redirects to provider.
  This is handled automatically by Ueberauth plug.
  Stores redirect_to from query params in session for callback.
  """
  def request(conn, %{"redirect_to" => redirect_to}) do
    # Store redirect_to in session if it's a valid internal redirect
    if YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
      conn
      |> put_session(:oauth_redirect_to, redirect_to)
    else
      conn
    end
  end

  def request(conn, _params) do
    conn
  end

  @doc """
  Handles OAuth callback phase for Google authentication.
  """
  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    # User cancelled or OAuth provider returned an error
    conn
    |> YscWeb.Flash.put_toast(
      :error,
      "Authentication was cancelled or failed. Please try again.",
      title: "Authentication"
    )
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    # Extract email from OAuth response
    email = extract_email(auth)

    if email do
      handle_oauth_success(conn, email, auth.provider)
    else
      conn
      |> YscWeb.Flash.put_toast(
        :error,
        "Unable to retrieve email from your account. Please contact support.",
        title: "Authentication"
      )
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(conn, _params) do
    # Unexpected state - no auth and no failure
    conn
    |> YscWeb.Flash.put_toast(
      :error,
      "Authentication error occurred. Please try again.",
      title: "Authentication"
    )
    |> redirect(to: ~p"/users/log-in")
  end

  # Private helper functions

  defp extract_email(%Ueberauth.Auth{info: info}) do
    # Try multiple fields where email might be stored
    info.email || info.raw["email"] || info.raw["emailAddress"]
  end

  defp handle_oauth_success(conn, email, provider) do
    case Accounts.get_user_by_email(email) do
      nil ->
        # User doesn't exist - use generic message to avoid user enumeration
        conn
        |> YscWeb.Flash.put_toast(
          :error,
          "Unable to sign in. Please try again or contact support.",
          title: "Authentication"
        )
        |> redirect(to: ~p"/users/log-in")

      user ->
        # Check if user is in an allowed state for login
        if user.state in [:pending_approval, :active] do
          # Set email_verified_at if not already set (OAuth providers verify emails)
          updated_user =
            if is_nil(user.email_verified_at) do
              case Accounts.mark_email_verified(user) do
                {:ok, updated} -> updated
                {:error, _} -> user
              end
            else
              user
            end

          # Get redirect_to from session if it was stored
          redirect_to = get_session(conn, :oauth_redirect_to)

          conn
          |> delete_session(:oauth_redirect_to)
          |> YscWeb.Flash.put_toast(
            :info,
            "Successfully signed in with #{String.capitalize(to_string(provider))}!",
            title: "Authentication"
          )
          |> put_session(:just_logged_in, true)
          |> UserAuth.log_in_user(
            updated_user,
            %{
              "method" => to_string(provider),
              "provider" => to_string(provider)
            },
            redirect_to
          )
        else
          # Account not in allowed state
          conn
          |> YscWeb.Flash.put_toast(
            :error,
            "Your account is not currently active.",
            title: "Authentication"
          )
          |> redirect(to: ~p"/users/log-in")
        end
    end
  end
end
