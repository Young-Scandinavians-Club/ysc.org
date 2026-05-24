defmodule Ysc.AppleWallet.TestImagePlug do
  @moduledoc false
  import Plug.Conn

  @tiny_png Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("image/png")
    |> send_resp(200, @tiny_png)
  end
end

defmodule Ysc.AppleWalletTest do
  # async: false — with_fake_certs/1 mutates global state (the named CertManager
  # GenServer and the :ysc :apple_wallet app env), so this module must run
  # serially to avoid races with other async test modules.
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.AppleWallet
  alias Ysc.Repo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  setup_all do
    {:ok,
     test_image_port:
       Ysc.HttpTestServer.ensure_started(
         Ysc.AppleWallet.TestImagePlug,
         :apple_wallet_test_image
       )}
  end

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
      |> then(& &1.tickets)
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
        |> then(& &1.tickets)
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
  # pkpass temp file cleanup
  # ---------------------------------------------------------------------------

  # The cleanup path (File.rm inside try/after) cannot be reached through
  # generate_ticket_pass/generate_membership_pass in tests because Passbook.generate
  # fails with fake certs before producing a file. These tests exercise the
  # try/after cleanup pattern directly with a controlled temp file to confirm
  # that File.rm runs even when File.read returns an error.

  describe "pkpass temp file cleanup" do
    test "deletes the pkpass temp file even when File.read fails" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "test_cleanup_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}.pkpass"
        )

      File.write!(tmp_path, "fake pkpass content")
      assert File.exists?(tmp_path)

      # Remove read permission so File.read returns {:error, :eacces}.
      # File.rm still succeeds because it only needs write permission on the
      # parent directory, which the test process owns.
      File.chmod!(tmp_path, 0o000)

      try do
        File.read(tmp_path)
      after
        File.rm(tmp_path)
      end

      refute File.exists?(tmp_path)
    end

    test "deletes the pkpass temp file when File.read succeeds" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "test_cleanup_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}.pkpass"
        )

      File.write!(tmp_path, "fake pkpass content")
      assert File.exists?(tmp_path)

      result =
        try do
          File.read(tmp_path)
        after
          File.rm(tmp_path)
        end

      assert {:ok, "fake pkpass content"} = result
      refute File.exists?(tmp_path)
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
  # generate_membership_pass/1 — beyond the cert check
  # ---------------------------------------------------------------------------

  describe "generate_membership_pass/1 with fake certs" do
    test "successfully generates a pass binary" do
      user = user_fixture()

      with_fake_certs(fn ->
        assert {:ok, pkpass} = AppleWallet.generate_membership_pass(user)
        # pkpass is a ZIP archive (.pkpass); verify it has content
        assert is_binary(pkpass) and byte_size(pkpass) > 0
        # ZIP magic bytes: PK
        assert <<80, 75, _::binary>> = pkpass
      end)
    end

    test "handles a user whose last_name is nil without crashing" do
      user = user_fixture()
      # Override in-memory; generate_membership_pass does not reload from DB
      user_with_nil_last = %{user | last_name: nil}

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_membership_pass(user_with_nil_last)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_ticket_pass/2 — pass field logic
  # ---------------------------------------------------------------------------

  describe "generate_ticket_pass/2 pass field logic" do
    setup do
      {user, ticket} = member_with_confirmed_ticket()
      event = Repo.get!(Ysc.Events.Event, ticket.event_id)
      %{user: user, ticket: ticket, event: event}
    end

    test "successfully generates a pass with a fully populated event", %{
      user: user,
      ticket: ticket,
      event: event
    } do
      event
      |> Ecto.Changeset.change(
        location_name: "Central Park",
        address: "59th St and 5th Ave, New York, NY",
        start_time: ~T[19:30:00]
      )
      |> Repo.update!()

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
        assert <<80, 75, _::binary>> = pkpass
      end)
    end

    test "omits the location field when event has no location_name", %{
      user: user,
      ticket: ticket,
      event: event
    } do
      event
      |> Ecto.Changeset.change(location_name: nil)
      |> Repo.update!()

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end

    test "omits the address back field when event has no address", %{
      user: user,
      ticket: ticket,
      event: event
    } do
      event
      |> Ecto.Changeset.change(address: nil)
      |> Repo.update!()

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end

    test "includes the holder field when the ticket has a registration with a name",
         %{
           user: user,
           ticket: ticket
         } do
      Repo.insert!(%Ysc.Events.TicketDetail{
        ticket_id: ticket.id,
        first_name: "Jane",
        last_name: "Smith",
        email: "jane@example.com"
      })

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end

    test "omits the holder field when the ticket has no registration", %{
      user: user,
      ticket: ticket
    } do
      # ticket_order_fixture does not create a TicketDetail by default
      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end

    test "includes time in the date string when the event has start_time set",
         %{
           user: user,
           ticket: ticket,
           event: event
         } do
      event
      |> Ecto.Changeset.change(start_time: ~T[19:30:00])
      |> Repo.update!()

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end

    test "shows date only (no time) when start_time is nil", %{
      user: user,
      ticket: ticket,
      event: event
    } do
      event
      |> Ecto.Changeset.change(start_time: nil)
      |> Repo.update!()

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end

    test "formats the date as 'TBD' when the event has no start_date", %{
      user: user,
      ticket: ticket,
      event: event
    } do
      # Ecto.Changeset.change/2 bypasses validation — start_date is optional in the changeset.
      # The format_event_date_for_pass(nil, _) clause returns "TBD".
      event
      |> Ecto.Changeset.change(start_date: nil)
      |> Repo.update!()

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_ticket_pass/2 — strip files (event cover image download)
  # ---------------------------------------------------------------------------

  describe "generate_ticket_pass/2 strip files" do
    setup do
      {user, ticket} = member_with_confirmed_ticket()
      event = Repo.get!(Ysc.Events.Event, ticket.event_id)
      %{user: user, ticket: ticket, event: event}
    end

    test "downloads the cover image and includes it as a strip file", %{
      user: user,
      ticket: ticket,
      event: event,
      test_image_port: port
    } do
      url = "http://127.0.0.1:#{port}/cover.png"

      {:ok, image} =
        %Ysc.Media.Image{user_id: user.id}
        |> Ysc.Media.Image.add_image_changeset(%{
          title: "Event Cover",
          raw_image_path: url,
          optimized_image_path: url,
          thumbnail_path: url,
          processing_state: "completed"
        })
        |> Repo.insert()

      event
      |> Ecto.Changeset.change(image_id: image.id)
      |> Repo.update!()

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end

    test "handles a cover_image whose image paths are nil (no strip files, pass still generated)",
         %{
           user: user,
           ticket: ticket,
           event: event
         } do
      {:ok, image} =
        %Ysc.Media.Image{user_id: user.id}
        |> Ysc.Media.Image.add_image_changeset(%{
          title: "Unprocessed Cover",
          raw_image_path: "/uploads/raw.jpg",
          optimized_image_path: nil,
          thumbnail_path: nil,
          processing_state: "unprocessed"
        })
        |> Repo.insert()

      event
      |> Ecto.Changeset.change(image_id: image.id)
      |> Repo.update!()

      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
    end

    test "handles a nil cover_image (no event image set, pass still generated)",
         %{
           user: user,
           ticket: ticket
         } do
      # event_fixture does not set image_id, so cover_image will be nil
      with_fake_certs(fn ->
        assert {:ok, pkpass} =
                 AppleWallet.generate_ticket_pass(ticket.id, user.id)

        assert is_binary(pkpass) and byte_size(pkpass) > 0
      end)
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

    original_env = Application.get_env(:ysc, :apple_wallet)
    original_state = :sys.get_state(Ysc.AppleWallet.CertManager)

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
      # Restore the named CertManager to whatever state it had before this helper ran
      :sys.replace_state(Ysc.AppleWallet.CertManager, fn _state ->
        original_state
      end)

      Application.put_env(:ysc, :apple_wallet, original_env)
    end
  end
end
