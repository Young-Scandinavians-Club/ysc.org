defmodule Ysc.GooglePhotos do
  @moduledoc """
  Context for the admin Google Photos OAuth integration.
  """

  import Ecto.Query

  require Ysc.Logging

  alias Ysc.GooglePhotos.Connection
  alias Ysc.GooglePhotos.OAuth
  alias Ysc.GooglePhotos.TokenStore
  alias Ysc.Repo

  @doc "Returns true when OAuth client credentials are configured."
  def configured?, do: OAuth.configured?()

  @doc "Returns the singleton connection row, or nil."
  def get_connection do
    Repo.one(from c in Connection, where: c.key == ^Connection.singleton_key())
  end

  @doc """
  Returns connection status for the admin UI.

  Map keys: `:connected`, `:account_email`, `:connected_at`, `:scopes`, `:oauth_configured`
  """
  def connection_status do
    connection = get_connection()

    %{
      oauth_configured: configured?(),
      connected: not is_nil(connection),
      account_email: connection && connection.account_email,
      connected_at: connection && connection.connected_at,
      scopes: connection && connection.scopes
    }
  end

  @doc """
  Persists OAuth tokens after a successful authorization callback.

  `token_map` must include `:access_token`, and should include `:refresh_token` on
  first connect. `:scope` is optional (from Google's token response).
  """
  def connect!(token_map, user_id, account_email) do
    existing = get_connection()

    refresh_token =
      Map.get(token_map, :refresh_token) ||
        Map.get(token_map, "refresh_token") ||
        (existing && existing.refresh_token)

    if is_nil(refresh_token) or refresh_token == "" do
      raise ArgumentError,
            "Google Photos connect requires a refresh_token; disconnect and reconnect with prompt=consent"
    end

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    scopes = Map.get(token_map, :scope) || Map.get(token_map, "scope")

    attrs = %{
      key: Connection.singleton_key(),
      refresh_token: refresh_token,
      account_email: account_email,
      scopes: scopes,
      connected_at: now
    }

    case existing do
      nil ->
        %Connection{}
        |> Connection.connect_changeset(attrs, user_id)
        |> Repo.insert!()

      row ->
        row
        |> Connection.connect_changeset(attrs, user_id)
        |> Repo.update!()
    end
    |> tap(fn _ -> TokenStore.reload() end)
  end

  @doc "Removes stored credentials and clears the in-memory token cache."
  def disconnect! do
    case get_connection() do
      nil ->
        :ok

      connection ->
        Repo.delete!(connection)
    end

    TokenStore.reload()
    :ok
  end

  @doc "Returns true when dev stub mode is enabled (dev by default; test when configured)."
  def dev_stub_enabled? do
    cond do
      Ysc.Env.dev?() -> google_photos_config()[:dev_stub] != false
      Ysc.Env.test?() -> google_photos_config()[:dev_stub] == true
      true -> false
    end
  end

  @doc "Returns true when photo uploads can proceed (connected or dev stub)."
  def uploads_available? do
    get_connection() != nil or dev_stub_enabled?()
  end

  @doc "Returns a valid access token via `TokenStore`, or a dev stub token when stubbing."
  def get_access_token do
    case TokenStore.get_access_token() do
      {:ok, token} ->
        {:ok, token}

      {:error, :not_connected} ->
        if dev_stub_enabled?(),
          do: {:ok, "dev-stub-token"},
          else: {:error, :not_connected}

      other ->
        other
    end
  end

  defp google_photos_config do
    Application.get_env(:ysc, :google_photos, [])
  end

  @doc """
  Verifies the integration: refreshes token if needed, calls Photos API, returns user email.
  """
  def test_connection do
    with {:ok, access_token} <- get_access_token(),
         :ok <- OAuth.test_photos_api(access_token),
         {:ok, email} <- OAuth.fetch_userinfo(access_token) do
      {:ok, %{email: email}}
    end
  end

  @doc """
  Seeds the connection from `GOOGLE_PHOTOS_REFRESH_TOKEN` when the DB is empty (dev convenience).
  """
  def maybe_seed_from_env do
    if get_connection() == nil do
      case System.get_env("GOOGLE_PHOTOS_REFRESH_TOKEN") do
        token when is_binary(token) and token != "" ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          %Connection{}
          |> Connection.changeset(%{
            key: Connection.singleton_key(),
            refresh_token: token,
            connected_at: now,
            scopes: Enum.join(OAuth.photos_api_scopes(), " ")
          })
          |> Repo.insert()

          TokenStore.reload()

        _ ->
          :ok
      end
    else
      :ok
    end
  rescue
    error ->
      Ysc.Logging.warning("Google Photos: failed to seed from env",
        error: inspect(error)
      )

      :ok
  end
end
