defmodule Ysc.GoogleWallet.Credentials do
  @moduledoc """
  GenServer that loads and caches Google Wallet service account credentials at startup.

  Reads GOOGLE_WALLET_CREDENTIALS_JSON (full JSON content of a Google service account
  key file) and GOOGLE_WALLET_ISSUER_ID from the application config. If either is
  missing or the JSON is malformed, the server starts in a degraded state and all
  callers receive `{:error, :not_configured}`.

  Also exposes `goth_child_spec/0` for the application supervisor to conditionally
  start the Goth OAuth2 token server only when credentials are present.
  """

  use GenServer

  require Ysc.Logging

  @google_wallet_scopes ["https://www.googleapis.com/auth/wallet_object.issuer"]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns `{:ok, credentials}` where credentials is a map with keys:
    - `:private_key` — PEM string of the RSA private key
    - `:private_key_id` — key ID from the service account JSON
    - `:client_email` — service account email address
    - `:issuer_id` — Google Wallet issuer ID from app config

  Returns `{:error, :not_configured}` if credentials are unavailable.
  """
  def get_credentials do
    GenServer.call(__MODULE__, :get_credentials)
  end

  @doc "Returns true if Google Wallet is configured and credentials are available."
  def configured? do
    match?({:ok, _}, get_credentials())
  end

  @doc """
  Returns the Goth child spec list for the application supervisor.

  Returns `[]` when credentials are not configured so the supervisor tree
  remains unaffected when Google Wallet is disabled.
  """
  def goth_child_spec do
    config = Application.get_env(:ysc, :google_wallet) || []
    credentials_json = config[:credentials_json]
    issuer_id = config[:issuer_id]

    if credentials_json && issuer_id do
      case Jason.decode(credentials_json) do
        {:ok, parsed} ->
          source =
            {:service_account, parsed, scopes: @google_wallet_scopes}

          [{Goth, name: Ysc.Goth, source: source}]

        {:error, reason} ->
          Ysc.Logging.error(
            "Google Wallet: failed to parse credentials JSON for Goth",
            extra: %{reason: inspect(reason)}
          )

          []
      end
    else
      []
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    config = Application.get_env(:ysc, :google_wallet) || []
    state = build_credentials(config[:credentials_json], config[:issuer_id])
    {:ok, state}
  end

  @impl true
  def handle_call(:get_credentials, _from, state) do
    {:reply, state, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_credentials(nil, _issuer_id), do: {:error, :not_configured}
  defp build_credentials(_json, nil), do: {:error, :not_configured}

  defp build_credentials(credentials_json, issuer_id) do
    case Jason.decode(credentials_json) do
      {:ok,
       %{
         "private_key" => private_key,
         "private_key_id" => private_key_id,
         "client_email" => client_email
       }} ->
        {:ok,
         %{
           private_key: private_key,
           private_key_id: private_key_id,
           client_email: client_email,
           issuer_id: issuer_id
         }}

      {:ok, _} ->
        Ysc.Logging.error(
          "Google Wallet: credentials JSON is missing required fields (private_key, private_key_id, client_email)"
        )

        {:error, :not_configured}

      {:error, reason} ->
        Ysc.Logging.error("Google Wallet: failed to parse credentials JSON",
          extra: %{reason: inspect(reason)}
        )

        {:error, :not_configured}
    end
  end
end
