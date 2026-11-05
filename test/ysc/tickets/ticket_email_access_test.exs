defmodule Ysc.Tickets.TicketEmailAccessTest do
  @moduledoc """
  Ticket emails must be usable without signing in: every ticket gets a QR code
  and wallet links behind a signed token, and each person a ticket was bought
  for gets their own email.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Repo
  alias Ysc.Tickets
  alias Ysc.Tickets.AccessToken
  alias YscWeb.Emails.TicketAccessHelpers
  alias YscWeb.Emails.TicketPurchaseConfirmation
  alias YscWeb.Emails.TicketRecipientNotification

  defp email_jobs do
    all_enqueued(worker: YscWeb.Workers.EmailNotifier)
  end

  defp jobs_for(template),
    do: Enum.filter(email_jobs(), &(&1.args["template"] == template))

  # Grants `count` tickets to a fresh user (no confirmation email), then
  # records the given emails as the attendee details of the tickets in order.
  defp order_with_attendees(attendee_emails) do
    Ysc.Ledgers.ensure_basic_accounts()
    admin = user_fixture()
    purchaser = user_fixture(%{first_name: "Pat", last_name: "Purchaser"})
    event = event_fixture()
    tier = ticket_tier_fixture(%{event_id: event.id, quantity: 10})

    {:ok, order} =
      Tickets.grant_admin_tickets(
        admin.id,
        purchaser.id,
        event.id,
        %{tier.id => length(attendee_emails)},
        skip_email: true
      )

    order.tickets
    |> Enum.sort_by(& &1.id)
    |> Enum.zip(attendee_emails)
    |> Enum.each(fn {ticket, email} ->
      {:ok, _} =
        Events.create_ticket_details([
          %{
            ticket_id: ticket.id,
            first_name: "Guest",
            last_name: String.upcase(String.first(email)),
            email: email
          }
        ])
    end)

    %{order: order, purchaser: purchaser, event: event}
  end

  describe "AccessToken" do
    test "round-trips each scope and rejects tampering" do
      assert {:ok, {:order, "o1"}} =
               AccessToken.verify(AccessToken.sign_order("o1"))

      assert {:ok, {:ticket, "t1"}} =
               AccessToken.verify(AccessToken.sign_ticket("t1"))

      assert {:ok, {:ticket, "t1"}} =
               AccessToken.verify(AccessToken.sign_tickets(["t1"]))

      assert {:ok, {:tickets, ["t1", "t2"]}} =
               AccessToken.verify(AccessToken.sign_tickets(["t2", "t1"]))

      assert {:error, :invalid} =
               AccessToken.verify(AccessToken.sign_order("o1") <> "x")

      assert {:error, :invalid} = AccessToken.verify(nil)
    end

    test "is not interchangeable with the door-scan QR token" do
      assert {:error, :invalid} =
               AccessToken.verify(Ysc.Scanning.QrToken.sign_ticket("t1"))

      assert {:error, :invalid} =
               Ysc.Scanning.QrToken.verify(AccessToken.sign_ticket("t1"))
    end

    test "verify_ticket/1 only accepts single-ticket tokens" do
      assert {:ok, "t1"} =
               AccessToken.verify_ticket(AccessToken.sign_ticket("t1"))

      assert {:error, :invalid} =
               AccessToken.verify_ticket(AccessToken.sign_order("o1"))
    end
  end

  describe "confirmation email" do
    test "includes a QR code card per ticket and a sign-in-free link" do
      %{order: order} = order_with_attendees(["a@example.com", "b@example.com"])

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order_for_email(order.id)
        )

      assert length(data.ticket_cards) == 2

      for card <- data.ticket_cards do
        assert card.qr_image_url =~ ~r{/t/[^/]+/qr\.png$}
        assert card.ticket_url =~ ~r{/t/[^/]+$}
      end

      assert data.tickets_qr_url =~ "/t/"
      assert {:ok, {:order, order_id}} = verify_url(data.tickets_qr_url)
      assert order_id == order.id

      html = TicketPurchaseConfirmation.render(data)
      assert html =~ "/qr.png"
    end

    test "admin-granted tickets get the granted wording" do
      %{order: order} = order_with_attendees(["a@example.com"])

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order_for_email(order.id)
        )

      assert data.granted
      html = TicketPurchaseConfirmation.render(data)
      assert html =~ "YSC has issued you tickets"
      refute html =~ "Thank you for your ticket purchase"
    end

    test "donation and unconfirmed tickets get no QR code" do
      %{order: order} = order_with_attendees(["a@example.com", "b@example.com"])

      order.tickets
      |> hd()
      |> Ecto.Changeset.change(status: :cancelled)
      |> Repo.update!()

      data =
        TicketPurchaseConfirmation.prepare_email_data(
          Tickets.get_ticket_order_for_email(order.id)
        )

      assert length(data.ticket_cards) == 1
    end
  end

  describe "guest emails" do
    test "each distinct attendee email other than the purchaser's gets one email with their tickets" do
      %{order: order, purchaser: purchaser} =
        order_with_attendees([
          "guest1@example.com",
          "Guest1@Example.com",
          "guest2@example.com",
          "placeholder@example.com"
        ])

      # The fourth attendee is the purchaser themselves.
      order.tickets
      |> Enum.sort_by(& &1.id)
      |> List.last()
      |> then(&Repo.get_by!(Ysc.Events.TicketDetail, ticket_id: &1.id))
      |> Ecto.Changeset.change(email: purchaser.email)
      |> Repo.update!()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Tickets.send_ticket_confirmation_email(order)

        assert [_purchaser_job] = jobs_for("ticket_purchase_confirmation")
        guest_jobs = jobs_for("ticket_recipient_notification")

        assert guest_jobs |> Enum.map(& &1.args["recipient"]) |> Enum.sort() ==
                 ["guest1@example.com", "guest2@example.com"]

        guest1 =
          Enum.find(guest_jobs, &(&1.args["recipient"] == "guest1@example.com"))

        assert length(guest1.args["params"]["ticket_cards"]) == 2
        assert guest1.args["params"]["purchaser_name"] == "Pat Purchaser"
        assert guest1.args["user_id"] == nil
      end)
    end

    test "sending twice does not duplicate guest emails" do
      %{order: order} = order_with_attendees(["guest@example.com"])

      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.send_ticket_confirmation_email(order)
        Tickets.send_ticket_confirmation_email(order)

        assert [_] = jobs_for("ticket_recipient_notification")
      end)
    end

    test "no guest email when every attendee is the purchaser" do
      %{order: order, purchaser: purchaser} =
        order_with_attendees(["x@example.com"])

      Repo.get_by!(Ysc.Events.TicketDetail, ticket_id: hd(order.tickets).id)
      |> Ecto.Changeset.change(email: String.upcase(purchaser.email))
      |> Repo.update!()

      Oban.Testing.with_testing_mode(:manual, fn ->
        Tickets.send_ticket_confirmation_email(order)

        assert [_] = jobs_for("ticket_purchase_confirmation")
        assert [] = jobs_for("ticket_recipient_notification")
      end)
    end

    test "admin grant to a member emails only that member" do
      Ysc.Ledgers.ensure_basic_accounts()
      admin = user_fixture()
      volunteer = user_fixture()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 10})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _order} =
                 Tickets.grant_admin_tickets(
                   admin.id,
                   volunteer.id,
                   event.id,
                   %{tier.id => 2}
                 )

        assert [job] = jobs_for("ticket_purchase_confirmation")
        assert job.args["recipient"] == volunteer.email
        assert length(job.args["params"]["ticket_cards"]) == 2
        assert [] = jobs_for("ticket_recipient_notification")
      end)
    end
  end

  describe "TicketRecipientNotification" do
    test "renders the purchaser, QR code and links for the guest's tickets" do
      %{order: order} = order_with_attendees(["guest@example.com"])
      order = Tickets.get_ticket_order_for_email(order.id)

      assert [recipient] = TicketRecipientNotification.recipients(order)
      data = TicketRecipientNotification.prepare_email_data(order, recipient)

      assert data.first_name == "Guest"
      assert data.purchaser_name == "Pat Purchaser"
      assert [card] = data.ticket_cards

      html = TicketRecipientNotification.render(data)
      assert html =~ "Pat Purchaser"
      assert html =~ card.qr_image_url
      refute html =~ "Open your ticket"
    end
  end

  describe "TicketAccessHelpers.ticket_cards/1" do
    test "wallet links are absent when the wallet isn't configured" do
      %{order: order} = order_with_attendees(["a@example.com"])
      order = Tickets.get_ticket_order_for_email(order.id)

      [card] = TicketAccessHelpers.ticket_cards(order.tickets)

      refute card.apple_wallet_url
      refute card.google_wallet_url
    end
  end

  defp verify_url(url) do
    url
    |> URI.parse()
    |> Map.fetch!(:path)
    |> String.replace_prefix("/t/", "")
    |> AccessToken.verify()
  end
end
