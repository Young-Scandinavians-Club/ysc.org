defmodule Ysc.GooglePhotos.TokenStore do
  @moduledoc """
  Caches short-lived Google Photos access tokens and refreshes them before expiry.

  Refresh tokens are read from the database in the calling process (sandbox-safe in tests);
  only access tokens are cached in this GenServer, keyed by the refresh token in use.
  """
  use GenServer

  require Ysc.Logging

  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.OAuth

  @refresh_buffer_seconds 120

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Clears the in-memory access token cache (call after connect/disconnect)."
  def reload do
    GenServer.cast(__MODULE__, :clear)
  end

  @doc """
  Seeds the cache with a freshly issued access token (e.g. after OAuth code exchange).

  Avoids an immediate refresh round-trip when the token is already valid.
  """
  def prime(access_token, expires_in, refresh_token)
      when is_binary(access_token) and is_integer(expires_in) and
             is_binary(refresh_token) do
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

    GenServer.call(
      __MODULE__,
      {:prime, access_token, expires_at, refresh_token}
    )
  end

  @doc """
  Returns `{:ok, access_token}` or `{:error, reason}`.

  Reasons include `:not_connected`, `:not_configured`, `:token_refresh_failed`, and
  `:refresh_token_revoked` (the stored grant was revoked; connection is cleared).
  """
  def get_access_token do
    case GooglePhotos.get_connection() do
      nil ->
        {:error, :not_connected}

      %{refresh_token: refresh_token} when not is_nil(refresh_token) ->
        GenServer.call(__MODULE__, {:get_access_token, refresh_token}, 30_000)

      _ ->
        {:error, :not_connected}
    end
  end

  @impl true
  def init(_opts) do
    {:ok, empty_cache()}
  end

  @impl true
  def handle_cast(:clear, _state) do
    {:noreply, empty_cache()}
  end

  @impl true
  def handle_call(
        {:prime, access_token, expires_at, refresh_token},
        _from,
        _state
      ) do
    {:reply, :ok,
     %{
       access_token: access_token,
       expires_at: expires_at,
       refresh_token: refresh_token
     }}
  end

  @impl true
  def handle_call({:get_access_token, refresh_token}, _from, state) do
    case ensure_access_token(state, refresh_token) do
      {:ok, access_token, new_state} ->
        {:reply, {:ok, access_token}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  defp empty_cache do
    %{access_token: nil, expires_at: nil, refresh_token: nil}
  end

  defp ensure_access_token(state, refresh_token) do
    if token_fresh?(state, refresh_token) do
      {:ok, state.access_token, state}
    else
      refresh_and_cache(state, refresh_token)
    end
  end

  defp token_fresh?(
         %{
           refresh_token: stored_refresh_token,
           access_token: token,
           expires_at: %DateTime{} = expires_at
         },
         refresh_token
       )
       when is_binary(token) and stored_refresh_token == refresh_token do
    DateTime.compare(
      DateTime.add(DateTime.utc_now(), @refresh_buffer_seconds, :second),
      expires_at
    ) ==
      :lt
  end

  defp token_fresh?(_, _), do: false

  defp refresh_and_cache(_state, refresh_token) do
    if OAuth.configured?() do
      case OAuth.refresh_access_token(refresh_token) do
        {:ok, tokens} ->
          %{
            access_token: access_token,
            expires_in: expires_in,
            refresh_token: rotated_refresh
          } = tokens

          effective_refresh =
            maybe_persist_rotated_refresh_token(refresh_token, rotated_refresh)

          expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

          new_state = %{
            access_token: access_token,
            expires_at: expires_at,
            refresh_token: effective_refresh
          }

          {:ok, access_token, new_state}

        {:error, :invalid_grant} ->
          GooglePhotos.handle_revoked_refresh_token!()

          {:error, :refresh_token_revoked, empty_cache()}

        {:error, reason} ->
          Ysc.Logging.error("Google Photos: failed to refresh access token",
            error: inspect(reason)
          )

          {:error, :token_refresh_failed, empty_cache()}
      end
    else
      {:error, :not_configured, empty_cache()}
    end
  end

  defp maybe_persist_rotated_refresh_token(current, nil), do: current

  defp maybe_persist_rotated_refresh_token(current, new) when current == new,
    do: current

  defp maybe_persist_rotated_refresh_token(_current, new) when is_binary(new) do
    GooglePhotos.update_refresh_token!(new)
    new
  end
end
