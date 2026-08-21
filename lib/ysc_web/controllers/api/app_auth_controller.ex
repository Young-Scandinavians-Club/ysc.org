defmodule YscWeb.Api.AppAuthController do
  @moduledoc """
  Sign-in endpoints for the admin/volunteer mobile app.

  Issues a long-lived bearer token (see `Ysc.Accounts.generate_user_mobile_token/1`)
  once a sign-in method succeeds. Only `:admin` and `:volunteer` accounts may
  receive a token — matches the web admin panel's `require_admin/2` split.

  Currently supports email + password. Google, Facebook, and passkey sign-in
  land in follow-up endpoints alongside this one.
  """
  use YscWeb, :controller

  alias Ysc.Accounts

  action_fallback YscWeb.Api.FallbackController

  def create_password_session(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    with :ok <- Ysc.AuthRateLimit.check_identifier(email),
         %Accounts.User{} = user <- Accounts.get_user_by_email_and_password(email, password),
         true <- user.role in [:admin, :volunteer],
         true <- Accounts.login_allowed_state?(user) do
      token = Accounts.generate_user_mobile_token(user)
      render(conn, :session, token: token, user: user)
    else
      {:error, :rate_limited, retry_after_sec} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_sec))
        |> put_status(:too_many_requests)
        |> json(%{error: "Too many attempts"})

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid email or password"})
    end
  end

  def create_password_session(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "email and password are required"})
  end

  def logout(conn, _params) do
    with ["Bearer " <> token | _] <- get_req_header(conn, "authorization") do
      Accounts.delete_user_mobile_token(String.trim(token))
    end

    send_resp(conn, :no_content, "")
  end
end
