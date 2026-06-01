defmodule Ysc.GooglePhotos.TokenStore do
  @moduledoc """
  Caches short-lived Google Photos access tokens and refreshes them before expiry.

  Refresh tokens are read from the database in the calling process (sandbox-safe in tests);
  only access tokens are cached in this GenServer.
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
  Returns `{:ok, access_token}` or `{:error, reason}`.

  Reasons include `:not_connected`, `:not_configured`, and `:token_refresh_failed`.
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
    {:ok, %{access_token: nil, expires_at: nil}}
  end

  @impl true
  def handle_cast(:clear, _state) do
    {:noreply, %{access_token: nil, expires_at: nil}}
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

  defp ensure_access_token(state, refresh_token) do
    if token_fresh?(state) do
      {:ok, state.access_token, state}
    else
      refresh_and_cache(state, refresh_token)
    end
  end

  defp token_fresh?(%{
         access_token: token,
         expires_at: %DateTime{} = expires_at
       })
       when is_binary(token) do
    DateTime.compare(
      DateTime.add(DateTime.utc_now(), @refresh_buffer_seconds),
      expires_at
    ) ==
      :lt
  end

  defp token_fresh?(_), do: false

  defp refresh_and_cache(state, refresh_token) do
    if OAuth.configured?() do
      case OAuth.refresh_access_token(refresh_token) do
        {:ok, %{access_token: access_token, expires_in: expires_in}} ->
          expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

          new_state = %{
            access_token: access_token,
            expires_at: expires_at
          }

          {:ok, access_token, new_state}

        {:error, reason} ->
          Ysc.Logging.error("Google Photos: failed to refresh access token",
            error: inspect(reason)
          )

          {:error, :token_refresh_failed,
           %{state | access_token: nil, expires_at: nil}}
      end
    else
      {:error, :not_configured, state}
    end
  end
end
