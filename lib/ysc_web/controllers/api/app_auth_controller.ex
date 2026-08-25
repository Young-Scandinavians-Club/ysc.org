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
  alias Ysc.Repo

  action_fallback YscWeb.Api.FallbackController

  def create_password_session(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    with :ok <- Ysc.AuthRateLimit.check_identifier(email),
         %Accounts.User{} = user <-
           Accounts.get_user_by_email_and_password(email, password),
         true <- user.role in [:admin, :volunteer],
         true <- Accounts.login_allowed_state?(user) do
      token = Accounts.generate_user_mobile_token(user)

      render(conn, :session,
        token: token,
        user: Repo.preload(user, :current_avatar)
      )
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

  @doc """
  Exchanges a one-time browser-handoff code (see `YscWeb.UserAuth.log_in_user/6`)
  for a mobile bearer token.

  The app opens the real web login page (password, Google, Facebook — whatever
  the user picks there) in a system browser tab; on success the web app
  redirects to the app's custom URL scheme with this code attached. The code
  proves the browser just completed a real login — it is single-use and
  expires within minutes — so this endpoint only needs to check it and the
  same role/state rules as password sign-in, not re-authenticate anything
  itself.

  `code_verifier` must be the same value the app generated before starting
  the login (sent then as `code_challenge`'s pre-image) — see
  `Ysc.Accounts.verify_and_consume_mobile_redirect_token/2` for why this
  matters: `ysc-admin://` is a private-use scheme another app could also
  register, and without this check that app could redeem a bare intercepted
  code itself.

  Deliberately not rate-limited: an identifier scoped to this request (the
  code, or even the requester's IP, since the threat model here is another
  app on the *same* device) would let whoever merely intercepted the bare
  code exhaust that budget with wrong-verifier guesses, denying the
  legitimate app's own correct attempt — turning a defense-in-depth measure
  into a worse DoS than the one it's meant to guard against. Unnecessary
  anyway: code_verifier is a random 256-bit value, so brute-forcing it
  within the code's 120-second validity window is computationally
  infeasible regardless.
  """
  def create_exchange_session(conn, %{
        "code" => code,
        "code_verifier" => code_verifier
      })
      when is_binary(code) and is_binary(code_verifier) do
    with {:ok, %Accounts.User{} = user} <-
           Accounts.verify_and_consume_mobile_redirect_token(
             code,
             code_verifier
           ),
         true <- user.role in [:admin, :volunteer],
         true <- Accounts.login_allowed_state?(user) do
      token = Accounts.generate_user_mobile_token(user)

      render(conn, :session,
        token: token,
        user: Repo.preload(user, :current_avatar)
      )
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or expired code"})
    end
  end

  def create_exchange_session(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "code and code_verifier are required"})
  end

  def logout(conn, _params) do
    with ["Bearer " <> token | _] <- get_req_header(conn, "authorization") do
      Accounts.delete_user_mobile_token(String.trim(token))
    end

    send_resp(conn, :no_content, "")
  end
end
