defmodule Ysc.AppleWallet.CertManager do
  @moduledoc """
  GenServer that manages Apple Wallet signing certificates.

  On startup, reads base64-encoded PEM certificates from Application config
  (populated from environment variables via runtime.exs), decodes them, and
  writes them to temporary files. This allows Fly.io secrets to be passed
  as env vars while satisfying the file-path API of the passbook library.

  If certificates are not configured, the GenServer starts but returns
  `{:error, :not_configured}` from all accessors — this gracefully disables
  the Apple Wallet feature in environments where certs are not set.
  """

  use GenServer

  require Ysc.Logging

  @wwdr_path Application.app_dir(:ysc, "priv/apple_wallet/wwdr.pem")

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns cert paths for generating ticket passes.

  Returns `{:ok, %{cert: path, key: path, password: string, wwdr: path}}`
  or `{:error, :not_configured}`.
  """
  def get_ticket_certs do
    GenServer.call(__MODULE__, :get_ticket_certs)
  end

  @doc """
  Returns cert paths for generating membership passes.

  Returns `{:ok, %{cert: path, key: path, password: string, wwdr: path}}`
  or `{:error, :not_configured}`.
  """
  def get_membership_certs do
    GenServer.call(__MODULE__, :get_membership_certs)
  end

  @doc """
  Returns true if ticket pass generation is configured.
  """
  def configured?(:ticket) do
    case get_ticket_certs() do
      {:ok, _} -> true
      _ -> false
    end
  end

  def configured?(:membership) do
    case get_membership_certs() do
      {:ok, _} -> true
      _ -> false
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    config = Application.get_env(:ysc, :apple_wallet) || []

    ticket_certs = build_certs(Keyword.get(config, :ticket), "ticket")

    membership_certs =
      build_certs(Keyword.get(config, :membership), "membership")

    {:ok, %{ticket: ticket_certs, membership: membership_certs}}
  end

  @impl true
  def handle_call(:get_ticket_certs, _from, state) do
    {:reply, state.ticket, state}
  end

  def handle_call(:get_membership_certs, _from, state) do
    {:reply, state.membership, state}
  end

  # --- Private ---

  defp build_certs(nil, _type), do: {:error, :not_configured}

  defp build_certs(%{} = config, type) do
    cert_b64 = Map.get(config, :cert_pem_b64)
    key_b64 = Map.get(config, :key_pem_b64)
    password = Map.get(config, :key_password, "")

    if cert_b64 && key_b64 do
      with {:ok, cert_pem} <- Base.decode64(cert_b64, ignore: :whitespace),
           {:ok, key_pem} <- Base.decode64(key_b64, ignore: :whitespace),
           {:ok, cert_path} <-
             write_temp_file("apple_wallet_#{type}_cert.pem", cert_pem),
           {:ok, key_path} <-
             write_temp_file("apple_wallet_#{type}_key.pem", key_pem) do
        {:ok,
         %{
           cert: cert_path,
           key: key_path,
           password: password || "",
           wwdr: @wwdr_path
         }}
      else
        :error ->
          Ysc.Logging.warning(
            "Apple Wallet: failed to decode base64 cert for #{type}"
          )

          {:error, :not_configured}

        {:error, reason} ->
          Ysc.Logging.warning(
            "Apple Wallet: failed to write cert file for #{type}",
            error: reason
          )

          {:error, :not_configured}
      end
    else
      {:error, :not_configured}
    end
  end

  defp write_temp_file(name, content) do
    unique = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    path = Path.join(System.tmp_dir!(), "#{name}_#{unique}")

    # sobelow_skip ["Traversal.FileModule"] - path is constructed from System.tmp_dir!() + a fixed internal prefix + random hex, not user input
    with :ok <- File.write(path, content),
         :ok <- File.chmod(path, 0o600) do
      {:ok, path}
    else
      {:error, reason} ->
        # sobelow_skip ["Traversal.FileModule"] - same internally-generated path as above
        File.rm(path)
        {:error, reason}
    end
  end
end
