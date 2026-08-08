defmodule QueryConsole.SSO do
  @moduledoc """
  YSC admin SSO client using authorization-code + PKCE and Req.

  Expected YSC endpoints (provider side):

  ## Authorize — GET `{authorize_url}`

  Query params:
  - `client_id`
  - `redirect_uri` (exact allowlisted callback)
  - `response_type=code`
  - `state` (opaque CSRF token)
  - `code_challenge` (S256)
  - `code_challenge_method=S256`

  Redirects the browser to `{redirect_uri}?code=...&state=...` on success.

  ## Token — POST `{token_url}`

  JSON body:
  ```json
  {
    "grant_type": "authorization_code",
    "code": "...",
    "redirect_uri": "...",
    "client_id": "...",
    "client_secret": "...",
    "code_verifier": "..."
  }
  ```

  Success JSON (200):
  ```json
  {
    "token_type": "bearer",
    "expires_in": 0,
    "user": {
      "id": "ulid",
      "email": "admin@example.com",
      "display_name": "Admin Name",
      "role": "admin",
      "state": "active"
    }
  }
  ```

  Errors: non-200 with `{"error": "...", "error_description": "..."}`.
  """

  @doc """
  Builds the authorize URL and returns `{url, state, code_verifier}` for the session.
  """
  def build_authorize_url do
    conf = config()
    state = random_token(32)
    code_verifier = random_token(64)
    code_challenge = s256_challenge(code_verifier)

    query =
      URI.encode_query(%{
        "client_id" => conf.client_id,
        "redirect_uri" => conf.redirect_uri,
        "response_type" => "code",
        "state" => state,
        "code_challenge" => code_challenge,
        "code_challenge_method" => "S256"
      })

    url = conf.authorize_url <> "?" <> query
    {url, state, code_verifier}
  end

  @doc """
  Exchanges an authorization code for user claims via the YSC token endpoint.
  """
  def exchange_code(code, code_verifier) when is_binary(code) and is_binary(code_verifier) do
    conf = config()

    body = %{
      grant_type: "authorization_code",
      code: code,
      redirect_uri: conf.redirect_uri,
      client_id: conf.client_id,
      client_secret: conf.client_secret,
      code_verifier: code_verifier
    }

    case Req.post(conf.token_url, json: body) do
      {:ok, %{status: 200, body: claims}} when is_map(claims) ->
        {:ok, normalize_claims(claims)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_exchange_failed, status, body}}

      {:error, reason} ->
        {:error, {:token_request_failed, reason}}
    end
  end

  def config do
    conf = Application.get_env(:query_console, __MODULE__, [])
    authorize_url = Keyword.fetch!(conf, :authorize_url)

    %{
      authorize_url: authorize_url,
      token_url: Keyword.fetch!(conf, :token_url),
      logout_url: Keyword.get(conf, :logout_url) || default_logout_url(authorize_url),
      client_id: Keyword.fetch!(conf, :client_id),
      client_secret: Keyword.fetch!(conf, :client_secret),
      redirect_uri: Keyword.fetch!(conf, :redirect_uri),
      base_url: Keyword.get(conf, :base_url, "http://localhost:4001"),
      post_logout_redirect_uri:
        Keyword.get(conf, :post_logout_redirect_uri) ||
          default_post_logout_redirect_uri(Keyword.get(conf, :base_url, "http://localhost:4001")),
      admin_url: Keyword.get(conf, :admin_url) || default_admin_url(authorize_url)
    }
  end

  @doc """
  Builds the YSC front-channel logout URL that clears the YSC session and
  returns the browser to the query console signed-out page.
  """
  def build_logout_url do
    conf = config()

    query =
      URI.encode_query(%{
        "client_id" => conf.client_id,
        "post_logout_redirect_uri" => conf.post_logout_redirect_uri
      })

    conf.logout_url <> "?" <> query
  end

  @doc "Public URL of the YSC admin dashboard."
  def admin_url, do: config().admin_url

  defp default_logout_url(authorize_url) do
    uri = URI.parse(authorize_url)
    URI.to_string(%{uri | path: "/oauth/logout", query: nil, fragment: nil})
  end

  defp default_admin_url(authorize_url) do
    uri = URI.parse(authorize_url)
    URI.to_string(%{uri | path: "/admin", query: nil, fragment: nil})
  end

  defp default_post_logout_redirect_uri(base_url) do
    String.trim_trailing(base_url, "/") <> "/auth/signed-out"
  end

  defp normalize_claims(claims) do
    user =
      case claims do
        %{"user" => %{} = nested} -> nested
        _ -> claims
      end

    %{
      "ysc_user_id" =>
        user["ysc_user_id"] || user["sub"] || user["id"] || claims["ysc_user_id"] ||
          claims["sub"] || claims["id"],
      "email" => user["email"] || claims["email"],
      "display_name" =>
        user["display_name"] || user["name"] || claims["display_name"] || claims["name"],
      "role" => user["role"] || claims["role"] || "admin",
      "state" => user["state"] || claims["state"]
    }
  end

  defp random_token(bytes) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp s256_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end
end
