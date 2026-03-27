defmodule Ysc.AppleWallet.CertManagerTest do
  use ExUnit.Case, async: true

  alias Ysc.AppleWallet.CertManager

  # The named CertManager GenServer is already running with no certs in the
  # test environment (env vars are not set), so all public API calls return
  # {:error, :not_configured}. These tests verify that unconfigured behaviour.

  describe "get_ticket_certs/0" do
    test "returns {:error, :not_configured} when no certs are set" do
      assert {:error, :not_configured} = CertManager.get_ticket_certs()
    end
  end

  describe "get_membership_certs/0" do
    test "returns {:error, :not_configured} when no certs are set" do
      assert {:error, :not_configured} = CertManager.get_membership_certs()
    end
  end

  describe "configured?/1" do
    test "returns false for :ticket when certs are not configured" do
      refute CertManager.configured?(:ticket)
    end

    test "returns false for :membership when certs are not configured" do
      refute CertManager.configured?(:membership)
    end
  end

  describe "init/1 with valid base64 certs" do
    # We test the GenServer init logic by starting a fresh (unnamed) process
    # with Application env temporarily patched.
    test "writes temp files and returns {:ok, paths} when valid base64 certs are provided" do
      cert_pem =
        "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----\n"

      key_pem =
        "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----\n"

      cert_b64 = Base.encode64(cert_pem)
      key_b64 = Base.encode64(key_pem)

      config = [
        team_id: "TESTTEAMID",
        org_name: "Test Org",
        ticket: %{
          cert_pem_b64: cert_b64,
          key_pem_b64: key_b64,
          key_password: nil,
          pass_type_id: "pass.com.test.ticket"
        },
        membership: %{
          cert_pem_b64: cert_b64,
          key_pem_b64: key_b64,
          key_password: "secret",
          pass_type_id: "pass.com.test.membership"
        }
      ]

      original = Application.get_env(:ysc, :apple_wallet)

      try do
        Application.put_env(:ysc, :apple_wallet, config)

        # Start an unnamed instance so it doesn't clash with the running CertManager
        {:ok, pid} = GenServer.start_link(CertManager, [])

        ticket_result = GenServer.call(pid, :get_ticket_certs)
        membership_result = GenServer.call(pid, :get_membership_certs)

        assert {:ok, ticket_certs} = ticket_result
        assert is_binary(ticket_certs.cert)
        assert is_binary(ticket_certs.key)
        assert ticket_certs.password == ""
        assert File.exists?(ticket_certs.cert)
        assert File.read!(ticket_certs.cert) == cert_pem

        assert {:ok, membership_certs} = membership_result
        assert membership_certs.password == "secret"
        assert File.exists?(membership_certs.key)

        GenServer.stop(pid)
      after
        Application.put_env(:ysc, :apple_wallet, original)
      end
    end

    test "returns {:error, :not_configured} when cert_pem_b64 is nil" do
      config = [
        ticket: %{
          cert_pem_b64: nil,
          key_pem_b64: Base.encode64("fake key"),
          key_password: nil,
          pass_type_id: "pass.com.test.ticket"
        },
        membership: %{
          cert_pem_b64: nil,
          key_pem_b64: nil,
          key_password: nil,
          pass_type_id: nil
        }
      ]

      original = Application.get_env(:ysc, :apple_wallet)

      try do
        Application.put_env(:ysc, :apple_wallet, config)
        {:ok, pid} = GenServer.start_link(CertManager, [])

        assert {:error, :not_configured} =
                 GenServer.call(pid, :get_ticket_certs)

        assert {:error, :not_configured} =
                 GenServer.call(pid, :get_membership_certs)

        GenServer.stop(pid)
      after
        Application.put_env(:ysc, :apple_wallet, original)
      end
    end

    test "returns {:error, :not_configured} when cert_pem_b64 is invalid base64" do
      config = [
        ticket: %{
          cert_pem_b64: "not!!valid!!base64",
          key_pem_b64: "also!!invalid",
          key_password: nil,
          pass_type_id: "pass.com.test.ticket"
        },
        membership: %{
          cert_pem_b64: nil,
          key_pem_b64: nil,
          key_password: nil,
          pass_type_id: nil
        }
      ]

      original = Application.get_env(:ysc, :apple_wallet)

      try do
        Application.put_env(:ysc, :apple_wallet, config)
        {:ok, pid} = GenServer.start_link(CertManager, [])

        assert {:error, :not_configured} =
                 GenServer.call(pid, :get_ticket_certs)

        GenServer.stop(pid)
      after
        Application.put_env(:ysc, :apple_wallet, original)
      end
    end

    test "returns {:error, :not_configured} when config is nil" do
      original = Application.get_env(:ysc, :apple_wallet)

      try do
        Application.delete_env(:ysc, :apple_wallet)
        {:ok, pid} = GenServer.start_link(CertManager, [])

        assert {:error, :not_configured} =
                 GenServer.call(pid, :get_ticket_certs)

        assert {:error, :not_configured} =
                 GenServer.call(pid, :get_membership_certs)

        GenServer.stop(pid)
      after
        if original do
          Application.put_env(:ysc, :apple_wallet, original)
        end
      end
    end
  end
end
