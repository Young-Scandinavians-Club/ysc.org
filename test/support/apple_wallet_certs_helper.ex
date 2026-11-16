defmodule Ysc.AppleWalletCertsHelper do
  @moduledoc """
  Temporarily injects Apple Wallet cert config so tests can reach pass
  generation. Mutates global app env and the named CertManager GenServer;
  use only from `async: false` tests.
  """

  def with_fake_certs(fun) when is_function(fun, 0) do
    fake_pem =
      Base.encode64(
        "-----BEGIN CERTIFICATE-----\nfake\n-----END CERTIFICATE-----\n"
      )

    config = [
      team_id: "TESTTEAM",
      org_name: "Test",
      ticket: %{
        cert_pem_b64: fake_pem,
        key_pem_b64: fake_pem,
        key_password: nil,
        pass_type_id: "pass.test.ticket"
      },
      membership: %{
        cert_pem_b64: fake_pem,
        key_pem_b64: fake_pem,
        key_password: nil,
        pass_type_id: "pass.test.membership"
      }
    ]

    original_env = Application.get_env(:ysc, :apple_wallet)
    original_state = :sys.get_state(Ysc.AppleWallet.CertManager)

    try do
      Application.put_env(:ysc, :apple_wallet, config)

      {:ok, pid} = GenServer.start_link(Ysc.AppleWallet.CertManager, [])
      ticket_certs = GenServer.call(pid, :get_ticket_certs)
      membership_certs = GenServer.call(pid, :get_membership_certs)
      GenServer.stop(pid)

      :sys.replace_state(Ysc.AppleWallet.CertManager, fn _state ->
        %{ticket: ticket_certs, membership: membership_certs}
      end)

      fun.()
    after
      :sys.replace_state(Ysc.AppleWallet.CertManager, fn _state ->
        original_state
      end)

      Application.put_env(:ysc, :apple_wallet, original_env)
    end
  end
end
