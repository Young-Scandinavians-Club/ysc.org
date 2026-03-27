defmodule Ysc.AppleWallet.CertManagerTest do
  # async: false — tests inside "init/1 with valid base64 certs" mutate the global
  # :ysc :apple_wallet application env via Application.put_env, which would race
  # with other async test modules reading the same key concurrently.
  # Restoration is already handled by try/after within each test.
  use ExUnit.Case, async: false

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

  # CertManager and AppleWallet resolve WWDR and icons via :code.priv_dir(:ysc)
  # at runtime so release images see the correct paths (not compile-time _build).

  describe "wallet pass asset files on disk" do
    test "icon and logo PNGs exist under priv/apple_wallet/icons" do
      icons_dir = Path.join([:code.priv_dir(:ysc), "apple_wallet", "icons"])

      for basename <- ~w(icon.png icon@2x.png icon@3x.png logo.png logo@2x.png) do
        path = Path.join(icons_dir, basename)
        assert File.exists?(path), "expected wallet asset at #{path}"
      end
    end

    test "WWDR PEM exists under priv/apple_wallet" do
      path = Path.join(:code.priv_dir(:ysc), "apple_wallet/wwdr.pem")
      assert File.exists?(path)
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

        expected_wwdr = Path.join(:code.priv_dir(:ysc), "apple_wallet/wwdr.pem")

        assert {:ok, ticket_certs} = ticket_result
        assert is_binary(ticket_certs.cert)
        assert is_binary(ticket_certs.key)
        assert ticket_certs.password == ""
        assert ticket_certs.wwdr == expected_wwdr
        assert File.exists?(ticket_certs.cert)
        assert File.read!(ticket_certs.cert) == cert_pem
        assert File.exists?(ticket_certs.wwdr)

        assert {:ok, membership_certs} = membership_result
        assert membership_certs.password == "secret"
        assert membership_certs.wwdr == expected_wwdr
        assert File.exists?(membership_certs.key)
        assert File.exists?(membership_certs.wwdr)

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
