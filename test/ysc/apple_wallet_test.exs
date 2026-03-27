defmodule Ysc.AppleWalletTest do
  # async: false — with_fake_certs/1 mutates global state (the named CertManager
  # GenServer and the :ysc :apple_wallet app env), so this module must run
  # serially to avoid races with other async test modules.
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.AppleWallet

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp member_with_confirmed_ticket do
    Ysc.Ledgers.ensure_basic_accounts()

    user =
      user_fixture()
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at:
          DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()
      |> Ysc.Repo.reload!()

    event = event_fixture()
    order = ticket_order_fixture(%{user: user, event: event})

    ticket =
      Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      |> Ysc.Repo.preload([:tickets])
      |> Map.fetch!(:tickets)
      |> hd()
      |> Ecto.Changeset.change(status: :confirmed)
      |> Ysc.Repo.update!()

    {user, ticket}
  end

  # ---------------------------------------------------------------------------
  # configured?/1
  # ---------------------------------------------------------------------------

  describe "configured?/1" do
    test "returns false for :ticket when no certs are set in test env" do
      refute AppleWallet.configured?(:ticket)
    end

    test "returns false for :membership when no certs are set in test env" do
      refute AppleWallet.configured?(:membership)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_ticket_pass/2
  # ---------------------------------------------------------------------------

  describe "generate_ticket_pass/2" do
    test "returns {:error, :not_configured} when Apple Wallet certs are not set" do
      {user, ticket} = member_with_confirmed_ticket()

      assert {:error, :not_configured} =
               AppleWallet.generate_ticket_pass(ticket.id, user.id)
    end

    test "returns {:error, :not_configured} for any ticket_id when certs not set" do
      user = user_fixture()

      assert {:error, :not_configured} =
               AppleWallet.generate_ticket_pass("nonexistent-id", user.id)
    end

    test "returns {:error, :not_found} when ticket does not belong to the user (certs injected)" do
      {_owner, ticket} = member_with_confirmed_ticket()
      other_user = user_fixture()

      with_fake_certs(fn ->
        assert {:error, :not_found} =
                 AppleWallet.generate_ticket_pass(ticket.id, other_user.id)
      end)
    end

    test "returns {:error, :not_found} for a non-existent ticket ID (certs injected)" do
      user = user_fixture()

      with_fake_certs(fn ->
        assert {:error, :not_found} =
                 AppleWallet.generate_ticket_pass(Ecto.ULID.generate(), user.id)
      end)
    end

    test "returns {:error, :not_found} for a non-confirmed (pending) ticket (certs injected)" do
      Ysc.Ledgers.ensure_basic_accounts()

      user =
        user_fixture()
        |> Ecto.Changeset.change(
          lifetime_membership_awarded_at:
            DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Ysc.Repo.update!()
        |> Ysc.Repo.reload!()

      event = event_fixture()
      order = ticket_order_fixture(%{user: user, event: event})

      pending_ticket =
        Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        |> Ysc.Repo.preload([:tickets])
        |> Map.fetch!(:tickets)
        |> hd()

      # Ticket stays :pending — not confirmed

      with_fake_certs(fn ->
        assert {:error, :not_found} =
                 AppleWallet.generate_ticket_pass(pending_ticket.id, user.id)
      end)
    end

    test "returns {:error, :not_found} for a cancelled ticket (certs injected)" do
      {user, ticket} = member_with_confirmed_ticket()

      cancelled =
        ticket
        |> Ecto.Changeset.change(status: :cancelled)
        |> Ysc.Repo.update!()

      with_fake_certs(fn ->
        assert {:error, :not_found} =
                 AppleWallet.generate_ticket_pass(cancelled.id, user.id)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_membership_pass/1
  # ---------------------------------------------------------------------------

  describe "generate_membership_pass/1" do
    test "returns {:error, :not_configured} when Apple Wallet certs are not set" do
      user = user_fixture()

      assert {:error, :not_configured} =
               AppleWallet.generate_membership_pass(user)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Temporarily injects fake (non-signing) cert config so that CertManager
  # returns {:ok, certs}, allowing tests to reach code paths beyond the cert
  # check. The fake certs will cause Passbook.generate to fail (no real OpenSSL
  # signing), which is expected — we only need to reach the DB/logic layer.
  defp with_fake_certs(fun) do
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

    original = Application.get_env(:ysc, :apple_wallet)

    try do
      Application.put_env(:ysc, :apple_wallet, config)

      # Start a fresh CertManager process (unnamed) that reads the patched config
      {:ok, pid} = GenServer.start_link(Ysc.AppleWallet.CertManager, [])

      # Temporarily swap the named process's state by casting the fake cert state
      ticket_certs = GenServer.call(pid, :get_ticket_certs)
      membership_certs = GenServer.call(pid, :get_membership_certs)
      GenServer.stop(pid)

      # Patch the running (named) CertManager's state directly via :sys
      :sys.replace_state(Ysc.AppleWallet.CertManager, fn _state ->
        %{ticket: ticket_certs, membership: membership_certs}
      end)

      fun.()
    after
      # Restore the named CertManager to its original (unconfigured) state
      :sys.replace_state(Ysc.AppleWallet.CertManager, fn _state ->
        %{
          ticket: {:error, :not_configured},
          membership: {:error, :not_configured}
        }
      end)

      Application.put_env(:ysc, :apple_wallet, original)
    end
  end
end
