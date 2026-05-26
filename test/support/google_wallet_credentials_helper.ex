defmodule Ysc.GoogleWalletCredentialsHelper do
  @moduledoc """
  Temporarily injects Google Wallet credentials for tests that exercise
  save-URL generation. Mutates global app env and the Credentials GenServer;
  use only from `async: false` tests.
  """

  def with_google_wallet_credentials(fun) when is_function(fun, 0) do
    private_key_pem = generate_test_rsa_pem()

    credentials_json =
      Jason.encode!(%{
        "type" => "service_account",
        "project_id" => "test-project",
        "private_key_id" => "test-key-id",
        "private_key" => private_key_pem,
        "client_email" => "wallet-test@test-project.iam.gserviceaccount.com",
        "client_id" => "123456789"
      })

    issuer_id = "3388000000012345678"

    original_config = Application.get_env(:ysc, :google_wallet)
    original_state = :sys.get_state(Ysc.GoogleWallet.Credentials)

    try do
      Application.put_env(:ysc, :google_wallet,
        credentials_json: credentials_json,
        issuer_id: issuer_id
      )

      {:ok, pid} = GenServer.start_link(Ysc.GoogleWallet.Credentials, [])
      new_state = :sys.get_state(pid)
      GenServer.stop(pid)

      :sys.replace_state(Ysc.GoogleWallet.Credentials, fn _state ->
        new_state
      end)

      fun.()
    after
      :sys.replace_state(Ysc.GoogleWallet.Credentials, fn _state ->
        original_state
      end)

      Application.put_env(:ysc, :google_wallet, original_config)
    end
  end

  defp generate_test_rsa_pem do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    :public_key.pem_encode([pem_entry])
  end
end
