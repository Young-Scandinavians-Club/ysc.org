defmodule Ysc.GooglePhotos.OAuth do
  @moduledoc """
  Google OAuth 2.0 helpers for the Photos Library integration (admin account).
  """

  require Ysc.Logging

  @authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @userinfo_url "https://www.googleapis.com/oauth2/v2/userinfo"
  @photos_api_base "https://photoslibrary.googleapis.com/v1"

  @oauth_scopes [
    "https://www.googleapis.com/auth/photoslibrary.edit.appcreateddata",
    "https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
    "openid",
    "https://www.googleapis.com/auth/photoslibrary",
    "https://www.googleapis.com/auth/photoslibrary.appendonly",
    "https://www.googleapis.com/auth/photoslibrary.sharing",
    "https://www.googleapis.com/auth/photoslibrary.readonly",
    "https://www.googleapis.com/auth/photoslibrary.readonly.originals"
  ]

  @doc "Returns the space-separated OAuth scope string used in authorize requests."
  def scope_string, do: Enum.join(@oauth_scopes, " ")

  @doc "Returns true when client id and secret are configured."
  def configured? do
    config = Application.get_env(:ysc, :google_photos, [])

    client_id = config[:client_id]
    client_secret = config[:client_secret]

    present?(client_id) and present?(client_secret)
  end

  @doc "Builds the Google authorization URL for the given CSRF state."
  def authorize_url(state) when is_binary(state) do
    with {:ok, client_id} <- fetch_client_id(),
         {:ok, redirect_uri} <- fetch_redirect_uri() do
      query =
        %{
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: scope_string(),
          access_type: "offline",
          prompt: "consent",
          state: state
        }
        |> URI.encode_query()

      "#{@authorize_url}?#{query}"
    end
  end

  @doc "Exchanges an authorization code for tokens."
  def exchange_code(code) when is_binary(code) do
    token_request(%{
      grant_type: "authorization_code",
      code: code,
      redirect_uri: fetch_redirect_uri!()
    })
  end

  @doc "Refreshes an access token using a refresh token."
  def refresh_access_token(refresh_token) when is_binary(refresh_token) do
    token_request(%{
      grant_type: "refresh_token",
      refresh_token: refresh_token
    })
  end

  @doc "Fetches the Google account email for a bearer access token."
  def fetch_userinfo(access_token) when is_binary(access_token) do
    case Req.get(@userinfo_url,
           headers: [{"authorization", "Bearer #{access_token}"}],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: status, body: %{"email" => email}}}
      when status in 200..299 and is_binary(email) ->
        {:ok, email}

      {:ok, %{status: status, body: body}} ->
        Ysc.Logging.error("Google Photos: userinfo request failed",
          status: status,
          body: inspect(body, limit: 200)
        )

        {:error, :userinfo_failed}

      {:error, reason} ->
        Ysc.Logging.error("Google Photos: userinfo request error",
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc "Lists one album page to verify Photos API access."
  def test_photos_api(access_token) when is_binary(access_token) do
    url = "#{@photos_api_base}/albums?" <> URI.encode_query(%{pageSize: 1})

    case Req.get(url,
           headers: [{"authorization", "Bearer #{access_token}"}],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Ysc.Logging.error("Google Photos: albums test request failed",
          status: status,
          body: inspect(body, limit: 200)
        )

        {:error, {:api_error, status}}

      {:error, reason} ->
        Ysc.Logging.error("Google Photos: albums test request error",
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp token_request(params) do
    with {:ok, client_id} <- fetch_client_id(),
         {:ok, client_secret} <- fetch_client_secret() do
      body =
        params
        |> Map.put(:client_id, client_id)
        |> Map.put(:client_secret, client_secret)
        |> URI.encode_query()

      case Req.post(@token_url,
             body: body,
             headers: [{"content-type", "application/x-www-form-urlencoded"}],
             receive_timeout: 15_000
           ) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          parse_token_response(body)

        {:ok, %{status: status, body: body}} ->
          Ysc.Logging.error("Google Photos: token request failed",
            status: status,
            body: inspect(body, limit: 200)
          )

          {:error, {:token_error, status}}

        {:error, reason} ->
          Ysc.Logging.error("Google Photos: token request error",
            error: inspect(reason)
          )

          {:error, reason}
      end
    end
  end

  defp parse_token_response(body) when is_map(body) do
    access_token = Map.get(body, "access_token")
    refresh_token = Map.get(body, "refresh_token")
    expires_in = Map.get(body, "expires_in", 3600)
    scope = Map.get(body, "scope")

    cond do
      not is_binary(access_token) ->
        {:error, :invalid_token_response}

      true ->
        {:ok,
         %{
           access_token: access_token,
           refresh_token: refresh_token,
           expires_in: expires_in,
           scope: scope
         }}
    end
  end

  defp parse_token_response(body) do
    Ysc.Logging.error("Google Photos: unexpected token response",
      body: inspect(body, limit: 200)
    )

    {:error, :invalid_token_response}
  end

  defp fetch_client_id do
    case Application.get_env(:ysc, :google_photos, [])[:client_id] do
      id when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, :not_configured}
    end
  end

  defp fetch_client_secret do
    case Application.get_env(:ysc, :google_photos, [])[:client_secret] do
      secret when is_binary(secret) and secret != "" -> {:ok, secret}
      _ -> {:error, :not_configured}
    end
  end

  defp fetch_redirect_uri do
    case redirect_uri() do
      uri when is_binary(uri) and uri != "" -> {:ok, uri}
      _ -> {:error, :redirect_uri_not_configured}
    end
  end

  defp fetch_redirect_uri! do
    case fetch_redirect_uri() do
      {:ok, uri} ->
        uri

      {:error, reason} ->
        raise "Google Photos OAuth misconfigured: #{inspect(reason)}"
    end
  end

  defp redirect_uri do
    config = Application.get_env(:ysc, :google_photos, [])

    config[:redirect_uri] ||
      YscWeb.Endpoint.url() <> "/admin/integrations/google-photos/callback"
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
