defmodule YscWeb.Api.AppTicketsControllerTest do
  @moduledoc """
  Tests for the admin/volunteer mobile app's in-person ticket purchase
  endpoint (`AppTicketsController` + `AppTicketsJSON`).
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Accounts

  defp member_with_active_membership do
    Ysc.Ledgers.ensure_basic_accounts()

    user_fixture()
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()
  end

  setup %{conn: conn} do
    admin = user_fixture(%{role: :admin})
    token = Accounts.generate_user_mobile_token(admin)

    original_stripe_client = Application.get_env(:ysc, :stripe_client)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn}
  end

  describe "POST /api/v1/app/events/:event_id/tickets/payment_intent" do
    test "creates a ticket order and a card-present payment intent for a single tier",
         %{
           conn: conn
         } do
      member = member_with_active_membership()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        assert params.payment_method_types == ["card_present"]
        assert params.capture_method == "automatic"
        refute Map.has_key?(params, :automatic_payment_methods)
        assert params.amount == 5000

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_test_card_present",
           client_secret: "pi_test_card_present_secret",
           amount: 5000,
           currency: "usd"
         }}
      end)

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1}
        })

      assert %{
               "client_secret" => "pi_test_card_present_secret",
               "amount" => 5000,
               "ticket_order_id" => ticket_order_id
             } = json_response(response, 200)

      assert is_binary(ticket_order_id)
    end

    test "creates a single order across multiple tiers with different quantities",
         %{
           conn: conn
         } do
      member = member_with_active_membership()
      event = event_fixture()

      general =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "General",
          price: Money.new(50, :USD)
        })

      vip =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "VIP",
          price: Money.new(100, :USD)
        })

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        # 2 x $50 General + 1 x $100 VIP = $200
        assert params.amount == 20_000

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_multi",
           client_secret: "pi_multi_secret",
           amount: 20_000,
           currency: "usd"
         }}
      end)

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{general.id => 2, vip.id => 1}
        })

      assert %{"client_secret" => "pi_multi_secret", "amount" => 20_000} =
               json_response(response, 200)
    end

    test "returns an error when the member has no active membership", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      member = user_fixture()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1}
        })

      assert json_response(response, 422)
    end

    test "returns an error when a tier belongs to a different event", %{
      conn: conn
    } do
      member = member_with_active_membership()
      event = event_fixture()
      other_event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: other_event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1}
        })

      assert json_response(response, 422)
    end

    test "returns an error for a zero quantity", %{conn: conn} do
      member = member_with_active_membership()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 0}
        })

      assert %{"error" => "one or more selected ticket quantities are invalid"} =
               json_response(response, 422)
    end

    # Finding 48: donation values are cents in BookingLocker but this API
    # documents quantity — refuse rather than charge $0.50 for `50`.
    test "rejects donation tiers instead of treating quantity as cents", %{
      conn: conn
    } do
      member = member_with_active_membership()
      event = event_fixture()

      paid =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "GA",
          price: Money.new(50, :USD)
        })

      donation =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Donation",
          type: :donation,
          price: nil
        })

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{paid.id => 1, donation.id => 50}
        })

      assert %{
               "error" =>
                 "donation ticket tiers cannot be charged via the in-person app; collect donations on the website"
             } = json_response(response, 422)
    end

    test "returns 404 for an unknown event", %{conn: conn} do
      member = member_with_active_membership()

      response =
        post(
          conn,
          ~p"/api/v1/app/events/01ARZ3NDEKTSV4RRFFQ69G5FAV/tickets/payment_intent",
          %{
            "member_id" => member.id,
            "tiers" => %{"01ARZ3NDEKTSV4RRFFQ69G5FAV" => 1}
          }
        )

      assert %{"error" => "event not found"} = json_response(response, 404)
    end

    test "returns 404 for an unknown member", %{conn: conn} do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV",
          "tiers" => %{tier.id => 1}
        })

      assert %{"error" => "member not found"} = json_response(response, 404)
    end

    test "returns 400 when member_id is missing", %{conn: conn} do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "tiers" => %{tier.id => 1}
        })

      assert json_response(response, 400)
    end

    test "returns 400 when tiers is missing", %{conn: conn} do
      member = member_with_active_membership()
      event = event_fixture()

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id
        })

      assert json_response(response, 400)
    end

    test "returns 400 when tiers is empty", %{conn: conn} do
      member = member_with_active_membership()
      event = event_fixture()

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{}
        })

      assert json_response(response, 400)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> post(
          ~p"/api/v1/app/events/01ARZ3NDEKTSV4RRFFQ69G5FAV/tickets/payment_intent",
          %{
            "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV",
            "tiers" => %{"01ARZ3NDEKTSV4RRFFQ69G5FAV" => 1}
          }
        )

      assert json_response(response, 401)
    end
  end

  describe "POST /api/v1/app/events/:event_id/tickets/offline_order" do
    test "grants confirmed tickets, sends the email, and records the cash note",
         %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      member = member_with_active_membership()
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{event_id: event.id, price: Money.new(45, :USD)})

      response =
        Oban.Testing.with_testing_mode(:manual, fn ->
          post(
            conn,
            ~p"/api/v1/app/events/#{event.id}/tickets/offline_order",
            %{
              "member_id" => member.id,
              "tiers" => %{tier.id => 2},
              "payment_method" => "cash",
              "amount_collected_cents" => 9000,
              "note" => "paid at door"
            }
          )
        end)

      assert %{
               "status" => "completed",
               "ticket_count" => 2,
               "ticket_order_reference" => "ORD" <> _,
               "payment_channel" => "cash",
               "amount_collected" => "$90.00",
               "notes" => notes
             } = json_response(response, 200)

      assert notes =~ "In-person cash payment recorded via the admin app"
      assert notes =~ "paid at door"

      order = Ysc.Repo.get_by(Ysc.Tickets.TicketOrder, event_id: event.id)
      assert order.status == :completed
      assert order.total_amount == Money.new(0, :USD)
      assert order.payment_channel == "cash"

      assert Money.equal?(
               order.offline_amount_collected,
               Money.new(:USD, "90.00")
             )

      # For an offline sale the grantor is the acting volunteer/admin.
      assert order.granted_by_id

      tickets =
        Ysc.Events.Ticket
        |> Ysc.Repo.all()
        |> Enum.filter(&(&1.ticket_order_id == order.id))

      assert length(tickets) == 2
      assert Enum.all?(tickets, &(&1.status == :confirmed))

      # The email is sent by default (no skip_email) — that is the whole point
      # of routing offline sales through Tickets.grant_admin_tickets/5.
      assert Oban.Job
             |> Ysc.Repo.all()
             |> Enum.any?(
               &(&1.args["idempotency_key"] ==
                   "ticket_confirmation_#{order.id}")
             )
    end

    test "defaults the payment method to cash when omitted", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      member = member_with_active_membership()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1}
        })

      assert %{"payment_channel" => "cash"} = json_response(response, 200)
    end

    test "records a check sale with no amount collected", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      member = member_with_active_membership()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1},
          "payment_method" => "check"
        })

      assert %{
               "payment_channel" => "check",
               "amount_collected" => nil
             } = json_response(response, 200)

      order = Ysc.Repo.get_by(Ysc.Tickets.TicketOrder, event_id: event.id)
      assert order.payment_channel == "check"
      assert is_nil(order.offline_amount_collected)
    end

    test "rejects an unknown payment method", %{conn: conn} do
      member = member_with_active_membership()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1},
          "payment_method" => "zelle"
        })

      assert %{"error" => "payment_method must be one of: cash, check, other"} =
               json_response(response, 422)
    end

    test "rejects a sale to a member without an active membership", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      member = user_fixture()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1}
        })

      assert %{"error" => "member does not have an active membership"} =
               json_response(response, 422)
    end

    test "rejects donation tiers", %{conn: conn} do
      member = member_with_active_membership()
      event = event_fixture()
      paid = ticket_tier_fixture(%{event_id: event.id, name: "GA"})

      donation =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Donation",
          type: :donation,
          price: nil
        })

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => member.id,
          "tiers" => %{paid.id => 1, donation.id => 50}
        })

      assert json_response(response, 422)
    end

    test "returns 400 when tiers is missing", %{conn: conn} do
      member = member_with_active_membership()
      event = event_fixture()

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => member.id
        })

      assert json_response(response, 400)
    end

    test "returns 404 for an unknown member", %{conn: conn} do
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV",
          "tiers" => %{tier.id => 1}
        })

      assert %{"error" => "member not found"} = json_response(response, 404)
    end

    test "returns 401 without a bearer token", %{conn: conn} do
      response =
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> post(
          ~p"/api/v1/app/events/01ARZ3NDEKTSV4RRFFQ69G5FAV/tickets/offline_order",
          %{
            "member_id" => "01ARZ3NDEKTSV4RRFFQ69G5FAV",
            "tiers" => %{"01ARZ3NDEKTSV4RRFFQ69G5FAV" => 1}
          }
        )

      assert json_response(response, 401)
    end
  end
end
