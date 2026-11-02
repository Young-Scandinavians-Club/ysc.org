defmodule YscWeb.OAuthController do
  @moduledoc """
  OAuth authorization-code endpoints for first-party apps.

  * `GET /oauth/authorize` — browser; authenticated user (eligibility is per-client)
  * `POST /oauth/token` — confidential client token exchange
  * `GET /oauth/logout` — front-channel logout with allowlisted post-logout redirect

  `/oauth/query-console/*` routes remain as aliases for the Query Console app.
  """
  use YscWeb, :controller

  require Ysc.Logging

  alias Ysc.Accounts.AuthService
  alias Ysc.OAuth
  alias YscWeb.UserAuth

  @doc """
  Starts the authorization-code flow for a registered client.

  Uses `real_current_user` when impersonating so SSO always binds to the
  real account, never the impersonated subject. Per-client role/state rules
  are enforced in `Ysc.OAuth`.
  """
  def authorize(conn, params) do
    user = conn.assigns[:real_current_user] || conn.assigns[:current_user]

    if is_nil(user) do
      conn
      |> put_status(:unauthorized)
      |> text("Unauthorized")
    else
      case OAuth.create_authorization(user, params) do
        {:ok, redirect_url} ->
          redirect(conn, external: redirect_url)

        {:error, :not_eligible} ->
          conn
          |> put_status(:forbidden)
          |> text("Forbidden")

        {:error, reason} ->
          Ysc.Logging.info("OAuth authorize rejected",
            reason: reason,
            user_id: user.id,
            client_id: params["client_id"]
          )

          conn
          |> put_status(:bad_request)
          |> text(authorize_error_message(reason))
      end
    end
  end

  @doc """
  Clears the YSC session and redirects to an allowlisted client logout URI.

  Works whether or not a YSC session is present (idempotent).
  """
  def logout(conn, params) do
    with {:ok, post_logout_redirect_uri} <-
           OAuth.validate_logout_request(params),
         :ok <- ensure_top_level_navigation(conn, post_logout_redirect_uri) do
      do_logout(conn, post_logout_redirect_uri)
    else
      {:error, :subresource_request} ->
        # <img>, <iframe>, fetch(), etc. from another site must not be able to
        # sign the user out; only a real navigation (the client app redirecting
        # the browser here) may. Leave the session alone.
        Ysc.Logging.info("OAuth logout rejected", reason: :subresource_request)

        conn
        |> put_status(:forbidden)
        |> text("Forbidden")

      {:error, reason} ->
        Ysc.Logging.info("OAuth logout rejected", reason: reason)

        conn
        |> put_status(:bad_request)
        |> text(logout_error_message(reason))
    end
  end

  # Browsers send `Sec-Fetch-Dest: document` for top-level navigations and
  # something else (`image`, `iframe`, `empty`, ...) for subresource loads.
  #
  # Browsers that predate Fetch Metadata send no such header, which would let
  # any page sign them out with an `<img>` tag. For those, a signed-in user is
  # only logged out when the request was referred from the client app itself
  # (the origin of its allowlisted post-logout URL); a missing or foreign
  # Referer is refused. With no session there is nothing to log out.
  defp ensure_top_level_navigation(conn, post_logout_redirect_uri) do
    case get_req_header(conn, "sec-fetch-dest") do
      ["document"] ->
        :ok

      [] ->
        if signed_in?(conn) and
             not referred_from?(conn, post_logout_redirect_uri) do
          {:error, :subresource_request}
        else
          :ok
        end

      _ ->
        {:error, :subresource_request}
    end
  end

  defp signed_in?(conn) do
    not is_nil(conn.assigns[:real_current_user] || conn.assigns[:current_user])
  end

  defp referred_from?(conn, post_logout_redirect_uri) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{scheme: scheme, host: host, port: port} when is_binary(host) <-
           URI.parse(referer),
         %URI{scheme: ^scheme, host: ^host, port: ^port} <-
           URI.parse(post_logout_redirect_uri) do
      true
    else
      _ -> false
    end
  end

  defp do_logout(conn, post_logout_redirect_uri) do
    user = conn.assigns[:real_current_user] || conn.assigns[:current_user]

    if user do
      AuthService.log_logout(user, conn)
    end

    conn
    |> UserAuth.drop_user_session()
    |> redirect(external: post_logout_redirect_uri)
  end

  @doc """
  Exchanges an authorization code (+ PKCE verifier) for a user identity payload.
  """
  def token(conn, params) do
    {basic_id, basic_secret} = parse_basic_auth(conn)

    case OAuth.exchange_token(params, basic_id, basic_secret) do
      {:ok, payload} ->
        json(conn, payload)

      {:error, reason} ->
        Ysc.Logging.info("OAuth token exchange rejected", reason: reason)

        {status, error, description} = token_error_response(reason)

        conn
        |> put_status(status)
        |> json(%{"error" => error, "error_description" => description})
    end
  end

  defp parse_basic_auth(conn) do
    case Plug.BasicAuth.parse_basic_auth(conn) do
      {id, secret} when is_binary(id) and is_binary(secret) -> {id, secret}
      _ -> {nil, nil}
    end
  end

  defp authorize_error_message(:invalid_client), do: "Invalid client_id"

  defp authorize_error_message(:invalid_redirect_uri),
    do: "Invalid redirect_uri"

  defp authorize_error_message(:unsupported_response_type),
    do: "Unsupported response_type"

  defp authorize_error_message(:missing_state), do: "Missing state"
  defp authorize_error_message(:invalid_pkce), do: "Invalid PKCE parameters"

  defp logout_error_message(:invalid_client), do: "Invalid client_id"

  defp logout_error_message(:invalid_redirect_uri),
    do: "Invalid post_logout_redirect_uri"

  defp token_error_response(:invalid_client),
    do: {:unauthorized, "invalid_client", "Client authentication failed"}

  defp token_error_response(:unsupported_grant_type),
    do:
      {:bad_request, "unsupported_grant_type",
       "grant_type must be authorization_code"}

  defp token_error_response(:invalid_grant),
    do:
      {:bad_request, "invalid_grant",
       "Authorization code is invalid, expired, or already used"}

  defp token_error_response(:invalid_request),
    do:
      {:bad_request, "invalid_request", "Missing or invalid request parameters"}
end
