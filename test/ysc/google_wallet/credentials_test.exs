defmodule Ysc.GoogleWallet.CredentialsTest do
  use ExUnit.Case, async: false

  alias Ysc.GoogleWallet.Credentials

  # ---------------------------------------------------------------------------
  # configured?/0
  # ---------------------------------------------------------------------------

  describe "configured?/0" do
    test "returns false when no credentials are configured in test env" do
      refute Credentials.configured?()
    end
  end

  # ---------------------------------------------------------------------------
  # get_credentials/0
  # ---------------------------------------------------------------------------

  describe "get_credentials/0" do
    test "returns {:error, :not_configured} when no credentials are set" do
      assert {:error, :not_configured} = Credentials.get_credentials()
    end

    test "returns {:ok, credentials} when valid JSON and issuer_id are provided" do
      private_key_pem = generate_test_rsa_pem()

      credentials_json =
        Jason.encode!(%{
          "type" => "service_account",
          "project_id" => "test-project",
          "private_key_id" => "test-key-id-123",
          "private_key" => private_key_pem,
          "client_email" => "wallet@test-project.iam.gserviceaccount.com",
          "client_id" => "123456789"
        })

      with_credentials(credentials_json, "1234567890", fn ->
        assert {:ok, creds} = Credentials.get_credentials()
        assert creds.private_key == private_key_pem
        assert creds.private_key_id == "test-key-id-123"

        assert creds.client_email ==
                 "wallet@test-project.iam.gserviceaccount.com"

        assert creds.issuer_id == "1234567890"
      end)
    end

    test "returns {:error, :not_configured} when JSON is invalid" do
      with_credentials("not-valid-json", "1234567890", fn ->
        assert {:error, :not_configured} = Credentials.get_credentials()
      end)
    end

    test "returns {:error, :not_configured} when JSON is missing required fields" do
      incomplete_json = Jason.encode!(%{"type" => "service_account"})

      with_credentials(incomplete_json, "1234567890", fn ->
        assert {:error, :not_configured} = Credentials.get_credentials()
      end)
    end

    test "returns {:error, :not_configured} when issuer_id is nil" do
      valid_json = build_valid_credentials_json()

      with_credentials(valid_json, nil, fn ->
        assert {:error, :not_configured} = Credentials.get_credentials()
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # goth_child_spec/0
  # ---------------------------------------------------------------------------

  describe "goth_child_spec/0" do
    test "returns empty list when not configured" do
      assert [] = Credentials.goth_child_spec()
    end

    test "returns Goth child spec when credentials are available" do
      private_key_pem = generate_test_rsa_pem()

      credentials_json =
        Jason.encode!(%{
          "type" => "service_account",
          "private_key_id" => "key-id",
          "private_key" => private_key_pem,
          "client_email" => "wallet@test.iam.gserviceaccount.com",
          "client_id" => "123"
        })

      with_credentials(credentials_json, "1234567890", fn ->
        spec = Credentials.goth_child_spec()
        assert [{Goth, opts}] = spec
        assert opts[:name] == Ysc.Goth
        assert {:service_account, _, _} = opts[:source]
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp generate_test_rsa_pem do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    :public_key.pem_encode([pem_entry])
  end

  defp build_valid_credentials_json do
    private_key_pem = generate_test_rsa_pem()

    Jason.encode!(%{
      "type" => "service_account",
      "private_key_id" => "test-key-id",
      "private_key" => private_key_pem,
      "client_email" => "wallet@test.iam.gserviceaccount.com",
      "client_id" => "123"
    })
  end

  defp with_credentials(credentials_json, issuer_id, fun) do
    original_config = Application.get_env(:ysc, :google_wallet)
    original_state = :sys.get_state(Credentials)

    try do
      Application.put_env(:ysc, :google_wallet,
        credentials_json: credentials_json,
        issuer_id: issuer_id
      )

      {:ok, pid} = GenServer.start_link(Credentials, [])
      new_state = :sys.get_state(pid)
      GenServer.stop(pid)

      :sys.replace_state(Credentials, fn _state -> new_state end)

      fun.()
    after
      :sys.replace_state(Credentials, fn _state -> original_state end)
      Application.put_env(:ysc, :google_wallet, original_config)
    end
  end
end
