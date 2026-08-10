defmodule Ysc.GoogleWalletTest do
  # async: false — with_fake_credentials/1 mutates global state (the named Credentials
  # GenServer and the :ysc :google_wallet app env), so this module must run
  # serially to avoid races with other async test modules.
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import Ysc.TicketsFixtures

  alias Ysc.GoogleWallet

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
      |> then(& &1.tickets)
      |> hd()
      |> Ecto.Changeset.change(status: :confirmed)
      |> Ysc.Repo.update!()

    {user, ticket}
  end

  # ---------------------------------------------------------------------------
  # configured?/0
  # ---------------------------------------------------------------------------

  describe "configured?/0" do
    test "returns false when no credentials are configured in test env" do
      refute GoogleWallet.configured?()
    end
  end

  describe "configured?/1" do
    test "returns false for :ticket when no credentials are set" do
      refute GoogleWallet.configured?(:ticket)
    end

    test "returns false for :membership when no credentials are set" do
      refute GoogleWallet.configured?(:membership)
    end

    test "returns false for any other type" do
      refute GoogleWallet.configured?(:something_else)
      refute GoogleWallet.configured?(nil)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_ticket_save_url/2
  # ---------------------------------------------------------------------------

  describe "generate_ticket_save_url/2" do
    test "returns {:error, :not_configured} when credentials are not set" do
      {user, ticket} = member_with_confirmed_ticket()

      assert {:error, :not_configured} =
               GoogleWallet.generate_ticket_save_url(ticket.id, user.id)
    end

    test "returns {:error, :not_configured} for any ticket_id when credentials not set" do
      user = user_fixture()

      assert {:error, :not_configured} =
               GoogleWallet.generate_ticket_save_url("nonexistent-id", user.id)
    end

    test "returns {:error, :not_found} when ticket does not belong to the user (credentials injected)" do
      {_owner, ticket} = member_with_confirmed_ticket()
      other_user = user_fixture()

      with_fake_credentials(fn ->
        assert {:error, :not_found} =
                 GoogleWallet.generate_ticket_save_url(ticket.id, other_user.id)
      end)
    end

    test "returns {:error, :not_found} for a non-existent ticket ID (credentials injected)" do
      user = user_fixture()

      with_fake_credentials(fn ->
        assert {:error, :not_found} =
                 GoogleWallet.generate_ticket_save_url(
                   Ecto.ULID.generate(),
                   user.id
                 )
      end)
    end

    test "returns {:error, :not_found} for a non-confirmed (pending) ticket (credentials injected)" do
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

      with_fake_credentials(fn ->
        assert {:error, :not_found} =
                 GoogleWallet.generate_ticket_save_url(
                   pending_ticket.id,
                   user.id
                 )
      end)
    end

    test "returns {:ok, url} with a pay.google.com save URL for a valid confirmed ticket" do
      {user, ticket} = member_with_confirmed_ticket()

      with_fake_credentials(fn ->
        assert {:ok, url} =
                 GoogleWallet.generate_ticket_save_url(ticket.id, user.id)

        assert String.starts_with?(url, "https://pay.google.com/gp/v/save/")
      end)
    end

    test "returned JWT contains expected Google Wallet payload structure" do
      {user, ticket} = member_with_confirmed_ticket()

      with_fake_credentials(fn ->
        {:ok, url} = GoogleWallet.generate_ticket_save_url(ticket.id, user.id)

        jwt =
          String.replace_prefix(url, "https://pay.google.com/gp/v/save/", "")

        # Decode without verification to inspect claims shape
        [_header, payload_b64, _sig] = String.split(jwt, ".")
        {:ok, payload_json} = Base.url_decode64(payload_b64, padding: false)
        {:ok, claims} = Jason.decode(payload_json)

        assert claims["aud"] == "google"
        assert claims["typ"] == "savetowallet"
        assert is_integer(claims["iat"])
        assert is_map(claims["payload"])
        assert is_list(claims["payload"]["eventTicketClasses"])
        assert is_list(claims["payload"]["eventTicketObjects"])
        assert length(claims["payload"]["eventTicketClasses"]) == 1
        assert length(claims["payload"]["eventTicketObjects"]) == 1

        [ticket_class] = claims["payload"]["eventTicketClasses"]
        assert String.contains?(ticket_class["id"], "event-")

        [ticket_object] = claims["payload"]["eventTicketObjects"]
        assert String.contains?(ticket_object["id"], "ticket-")
        assert ticket_object["state"] == "ACTIVE"
        assert is_map(ticket_object["barcode"])
        assert ticket_object["barcode"]["type"] == "QR_CODE"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_ticket_save_urls/2
  # ---------------------------------------------------------------------------

  describe "generate_ticket_save_urls/2" do
    test "returns {:error, :not_configured} when credentials are not set" do
      {user, ticket} = member_with_confirmed_ticket()

      assert {:error, :not_configured} =
               GoogleWallet.generate_ticket_save_urls([ticket.id], user.id)
    end

    test "loads tickets in one batch and returns per-ticket results" do
      {user, ticket} = member_with_confirmed_ticket()

      with_fake_credentials(fn ->
        assert {:ok, results} =
                 GoogleWallet.generate_ticket_save_urls([ticket.id], user.id)

        assert {:ok, url} = Map.fetch!(results, ticket.id)
        assert String.starts_with?(url, "https://pay.google.com/gp/v/save/")
      end)
    end

    test "returns :not_found for tickets that do not belong to the user" do
      {_owner, ticket} = member_with_confirmed_ticket()
      other_user = user_fixture()

      with_fake_credentials(fn ->
        assert {:ok, results} =
                 GoogleWallet.generate_ticket_save_urls(
                   [ticket.id],
                   other_user.id
                 )

        assert {:error, :not_found} = Map.fetch!(results, ticket.id)
      end)
    end

    test "returns {:ok, %{}} for an empty ticket_id list without querying tickets" do
      user = user_fixture()

      with_fake_credentials(fn ->
        assert {:ok, %{}} = GoogleWallet.generate_ticket_save_urls([], user.id)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_ticket_save_url/2 — event cover image and venue rendering
  # ---------------------------------------------------------------------------

  describe "generate_ticket_save_url/2 payload details" do
    test "uses the optimized cover image and place_id venue, and includes the ticket holder name" do
      {user, ticket} = member_with_confirmed_ticket()

      image =
        %Ysc.Media.Image{user_id: user.id}
        |> Ysc.Media.Image.add_image_changeset(%{raw_image_path: "/uploads/raw.jpg"})
        |> Ysc.Repo.insert!()
        |> Ysc.Media.Image.processed_image_changeset(%{
          optimized_image_path: "/uploads/optimized.jpg"
        })
        |> Ysc.Repo.update!()

      Ysc.Repo.get!(Ysc.Events.Event, ticket.event_id)
      |> Ecto.Changeset.change(%{
        image_id: image.id,
        location_name: "  Clubhouse  ",
        place_id: "  ChIJ123  "
      })
      |> Ysc.Repo.update!()

      Ysc.Repo.insert!(%Ysc.Events.TicketDetail{
        ticket_id: ticket.id,
        first_name: "Ada",
        last_name: "Admin",
        email: "ada@example.com"
      })

      with_fake_credentials(fn ->
        {:ok, url} = GoogleWallet.generate_ticket_save_url(ticket.id, user.id)
        claims = decode_jwt_claims(url)

        [ticket_class] = claims["payload"]["eventTicketClasses"]

        assert ticket_class["heroImage"]["sourceUri"]["uri"] =~
                 "/uploads/optimized.jpg"

        assert ticket_class["venue"] == %{
                 "name" => %{
                   "defaultValue" => %{"language" => "en-US", "value" => "Clubhouse"}
                 },
                 "placeId" => "ChIJ123"
               }

        [ticket_object] = claims["payload"]["eventTicketObjects"]
        assert ticket_object["ticketHolderName"] == "Ada Admin"
      end)
    end

    test "falls back to the raw cover image and address venue when no optimized path or place_id exists" do
      {user, ticket} = member_with_confirmed_ticket()

      image =
        %Ysc.Media.Image{user_id: user.id}
        |> Ysc.Media.Image.add_image_changeset(%{
          raw_image_path: "https://cdn.example.com/raw.jpg"
        })
        |> Ysc.Repo.insert!()

      Ysc.Repo.get!(Ysc.Events.Event, ticket.event_id)
      |> Ecto.Changeset.change(%{
        image_id: image.id,
        location_name: "Clubhouse",
        address: "123 Main St"
      })
      |> Ysc.Repo.update!()

      with_fake_credentials(fn ->
        {:ok, url} = GoogleWallet.generate_ticket_save_url(ticket.id, user.id)
        claims = decode_jwt_claims(url)

        [ticket_class] = claims["payload"]["eventTicketClasses"]

        assert ticket_class["heroImage"]["sourceUri"]["uri"] ==
                 "https://cdn.example.com/raw.jpg"

        assert ticket_class["venue"] == %{
                 "name" => %{
                   "defaultValue" => %{"language" => "en-US", "value" => "Clubhouse"}
                 },
                 "address" => %{
                   "defaultValue" => %{"language" => "en-US", "value" => "123 Main St"}
                 }
               }

        [ticket_object] = claims["payload"]["eventTicketObjects"]
        # No TicketDetail row was created for this ticket.
        refute Map.has_key?(ticket_object, "ticketHolderName")
      end)
    end

    test "leaves an already-absolute http:// cover image path untouched" do
      {user, ticket} = member_with_confirmed_ticket()

      image =
        %Ysc.Media.Image{user_id: user.id}
        |> Ysc.Media.Image.add_image_changeset(%{
          raw_image_path: "http://cdn.example.com/raw.jpg"
        })
        |> Ysc.Repo.insert!()

      Ysc.Repo.get!(Ysc.Events.Event, ticket.event_id)
      |> Ecto.Changeset.change(%{image_id: image.id})
      |> Ysc.Repo.update!()

      with_fake_credentials(fn ->
        {:ok, url} = GoogleWallet.generate_ticket_save_url(ticket.id, user.id)
        claims = decode_jwt_claims(url)

        [ticket_class] = claims["payload"]["eventTicketClasses"]

        assert ticket_class["heroImage"]["sourceUri"]["uri"] ==
                 "http://cdn.example.com/raw.jpg"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_membership_save_url/1
  # ---------------------------------------------------------------------------

  describe "generate_membership_save_url/1" do
    test "returns {:error, :not_configured} when credentials are not set" do
      user = user_fixture()

      assert {:error, :not_configured} =
               GoogleWallet.generate_membership_save_url(user)
    end

    test "returns {:ok, url} with a pay.google.com save URL" do
      user = user_with_active_subscription()

      with_fake_credentials(fn ->
        assert {:ok, url} = GoogleWallet.generate_membership_save_url(user)
        assert String.starts_with?(url, "https://pay.google.com/gp/v/save/")
      end)
    end

    test "returned JWT contains expected Generic pass payload structure" do
      user = user_with_active_subscription()

      with_fake_credentials(fn ->
        {:ok, url} = GoogleWallet.generate_membership_save_url(user)

        jwt =
          String.replace_prefix(url, "https://pay.google.com/gp/v/save/", "")

        [_header, payload_b64, _sig] = String.split(jwt, ".")
        {:ok, payload_json} = Base.url_decode64(payload_b64, padding: false)
        {:ok, claims} = Jason.decode(payload_json)

        assert claims["aud"] == "google"
        assert claims["typ"] == "savetowallet"
        assert is_map(claims["payload"])
        assert is_list(claims["payload"]["genericClasses"])
        assert is_list(claims["payload"]["genericObjects"])
        assert length(claims["payload"]["genericClasses"]) == 1
        assert length(claims["payload"]["genericObjects"]) == 1

        [generic_class] = claims["payload"]["genericClasses"]
        assert String.contains?(generic_class["id"], "ysc-membership")

        [generic_object] = claims["payload"]["genericObjects"]
        assert String.contains?(generic_object["id"], "membership-")
        assert generic_object["state"] == "ACTIVE"
        assert is_map(generic_object["barcode"])
        assert generic_object["barcode"]["type"] == "QR_CODE"
      end)
    end

    test "returned JWT has state INACTIVE when user has no active subscription" do
      user = user_fixture()

      with_fake_credentials(fn ->
        {:ok, url} = GoogleWallet.generate_membership_save_url(user)

        jwt =
          String.replace_prefix(url, "https://pay.google.com/gp/v/save/", "")

        [_header, payload_b64, _sig] = String.split(jwt, ".")
        {:ok, payload_json} = Base.url_decode64(payload_b64, padding: false)
        {:ok, claims} = Jason.decode(payload_json)

        [generic_object] = claims["payload"]["genericObjects"]
        assert generic_object["state"] == "INACTIVE"
      end)
    end

    test "validTimeInterval has only an end date when current_period_start is nil" do
      user = user_fixture()
      now = DateTime.truncate(DateTime.utc_now(), :second)

      {:ok, _sub} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: user.id,
          name: "Membership",
          stripe_id: "sub_test_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          start_date: now,
          current_period_start: nil,
          current_period_end: DateTime.add(now, 30, :day)
        })

      with_fake_credentials(fn ->
        {:ok, url} = GoogleWallet.generate_membership_save_url(user)
        claims = decode_jwt_claims(url)

        [generic_object] = claims["payload"]["genericObjects"]
        interval = generic_object["validTimeInterval"]

        assert Map.has_key?(interval, "end")
        refute Map.has_key?(interval, "start")
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Decodes the (unverified) JWT payload embedded in a Google Wallet save URL.
  defp decode_jwt_claims(url) do
    jwt = String.replace_prefix(url, "https://pay.google.com/gp/v/save/", "")
    [_header, payload_b64, _sig] = String.split(jwt, ".")
    {:ok, payload_json} = Base.url_decode64(payload_b64, padding: false)
    {:ok, claims} = Jason.decode(payload_json)
    claims
  end

  # Creates a user with an active Stripe subscription so membership_wallet_info/1
  # returns state "ACTIVE" and a valid validity window.
  defp user_with_active_subscription do
    user = user_fixture()
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {:ok, _sub} =
      Ysc.Subscriptions.create_subscription(%{
        user_id: user.id,
        name: "Membership",
        stripe_id: "sub_test_#{System.unique_integer([:positive])}",
        stripe_status: "active",
        start_date: now,
        current_period_start: now,
        current_period_end: DateTime.add(now, 30, :day)
      })

    user
  end

  # Generates a real RSA-2048 private key in PEM format for test JWT signing.
  defp generate_test_rsa_pem do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    :public_key.pem_encode([pem_entry])
  end

  # Temporarily injects fake (but real) credentials so that Credentials returns
  # {:ok, creds}, allowing tests to reach code paths beyond the credentials check.
  # Uses a real RSA key so JWT signing works end-to-end.
  defp with_fake_credentials(fun) do
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
end
