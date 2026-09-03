defmodule YscWeb.Api.AppTicketsControllerTest do
  @moduledoc """
  Tests for the admin/volunteer mobile app's in-person ticket purchase
  endpoint (`AppTicketsController` + `AppTicketsJSON`).
  """
  use YscWeb.ConnCase, async: false

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Subscriptions

  defp member_with_active_membership do
    Ysc.Ledgers.ensure_basic_accounts()

    user_fixture()
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at:
        DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()
  end

  defp give_single_membership(user) do
    Ysc.Ledgers.ensure_basic_accounts()
    plans = Application.fetch_env!(:ysc, :membership_plans)
    single = Enum.find(plans, &(&1.id == :single))

    {:ok, subscription} =
      Subscriptions.create_subscription(%{
        user_id: user.id,
        stripe_id: "sub_single_#{System.unique_integer([:positive])}",
        stripe_status: "active",
        name: "Membership",
        current_period_start: DateTime.truncate(DateTime.utc_now(), :second),
        current_period_end:
          DateTime.utc_now()
          |> DateTime.add(30, :day)
          |> DateTime.truncate(:second)
      })

    {:ok, _} =
      Subscriptions.create_subscription_item(%{
        subscription_id: subscription.id,
        stripe_id: "si_single_#{System.unique_integer([:positive])}",
        stripe_product_id: "prod_single",
        stripe_price_id: single.stripe_price_id,
        quantity: 1
      })

    MembershipCache.invalidate_user(user.id)
    user
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

    test "card-present checkout loads the event and selected tiers once", %{
      conn: conn
    } do
      member = member_with_active_membership()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_reuse",
           client_secret: "pi_reuse_secret",
           amount: 5000,
           currency: "usd"
         }}
      end)

      {response, event_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            post(
              conn,
              ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent",
              %{"member_id" => member.id, "tiers" => %{tier.id => 1}}
            )
          end,
          pattern: ~r/FROM "events" AS e0 WHERE \(e0\."id" = \$/,
          caller_pids: [self()]
        )

      assert json_response(response, 200)
      assert event_lookups == 1
    end

    test "card-present checkout loads selected tiers once including PaymentIntent repricing",
         %{
           conn: conn
         } do
      member = member_with_active_membership()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_tier_reuse",
           client_secret: "pi_tier_reuse_secret",
           amount: 5000,
           currency: "usd"
         }}
      end)

      {response, tier_lookups} =
        Ysc.QueryCounter.with_query_counter(
          fn ->
            post(
              conn,
              ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent",
              %{"member_id" => member.id, "tiers" => %{tier.id => 1}}
            )
          end,
          pattern: ~r/FROM "ticket_tiers"/,
          caller_pids: [self()]
        )

      assert json_response(response, 200)
      # load_selected_tiers once. atomic_booking, capacity_warnings, and
      # PaymentIntent repricing reuse those same-request structs.
      assert tier_lookups == 1
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

    test "sells tickets for an event that has already started, with no warnings",
         %{conn: conn} do
      member = member_with_active_membership()

      event =
        event_fixture(%{
          start_date: DateTime.add(DateTime.utc_now(), -2, :day)
        })

      tier = ticket_tier_fixture(%{event_id: event.id})

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_started",
           client_secret: "pi_started_secret",
           amount: 5000,
           currency: "usd"
         }}
      end)

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1}
        })

      assert %{"client_secret" => "pi_started_secret", "warnings" => []} =
               json_response(response, 200)
    end

    test "sells past a tier's sale-start window, with no warnings", %{
      conn: conn
    } do
      member = member_with_active_membership()
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          start_date: DateTime.add(DateTime.utc_now(), 2, :day)
        })

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_payment_intent, fn _params, _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_not_yet_on_sale",
           client_secret: "pi_not_yet_on_sale_secret",
           amount: 5000,
           currency: "usd"
         }}
      end)

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1}
        })

      assert %{"client_secret" => "pi_not_yet_on_sale_secret", "warnings" => []} =
               json_response(response, 200)
    end

    test "sells past tier and event capacity, returning warnings", %{conn: conn} do
      member = member_with_active_membership()
      event = event_fixture(%{max_attendees: 1})
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 2})

      Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

      Mox.expect(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        # 5 x $50 = $250, still charged in full despite exceeding capacity.
        assert params.amount == 25_000

        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_oversell",
           client_secret: "pi_oversell_secret",
           amount: 25_000,
           currency: "usd"
         }}
      end)

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 5}
        })

      assert %{"client_secret" => "pi_oversell_secret", "warnings" => warnings} =
               json_response(response, 200)

      assert length(warnings) == 2
      assert Enum.any?(warnings, &(&1 =~ "exceeds the 2 remaining by 3"))
      assert Enum.any?(warnings, &(&1 =~ "Event capacity"))

      tickets =
        Ysc.Events.Ticket
        |> Ysc.Repo.all()
        |> Enum.filter(&(&1.ticket_tier_id == tier.id))

      assert length(tickets) == 5
    end

    test "still rejects a cancelled event", %{conn: conn} do
      member = member_with_active_membership()
      event = event_fixture(%{state: :published})
      tier = ticket_tier_fixture(%{event_id: event.id})
      {:ok, _} = Ysc.Events.update_event(event, %{state: :cancelled})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1}
        })

      assert json_response(response, 422)
    end

    # Card-present door sale forwards the same-request event/tiers into
    # create_ticket_order/4. Member-only rules still run; these used to 500
    # because FallbackController did not map the atoms.
    test "returns 422 when a Single member exceeds the members-only per-event limit",
         %{conn: conn} do
      member = give_single_membership(user_fixture())
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Member",
          member_only: true
        })

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/payment_intent", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 2}
        })

      assert %{
               "error" =>
                 "this membership includes one members-only ticket per event"
             } = json_response(response, 422)
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

    test "records an other in-person payment channel", %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      member = member_with_active_membership()
      event = event_fixture()
      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1},
          "payment_method" => "other",
          "note" => "Venmo at the door"
        })

      assert %{
               "payment_channel" => "other",
               "amount_collected" => nil,
               "notes" => notes
             } = json_response(response, 200)

      assert notes =~ "Venmo at the door"

      order = Ysc.Repo.get_by(Ysc.Tickets.TicketOrder, event_id: event.id)
      assert order.payment_channel == "other"
      assert order.total_amount == Money.new(0, :USD)
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

    test "grants tickets for an event that has already started, with no warnings",
         %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()
      member = member_with_active_membership()

      event =
        event_fixture(%{
          start_date: DateTime.add(DateTime.utc_now(), -2, :day)
        })

      tier = ticket_tier_fixture(%{event_id: event.id})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 1}
        })

      assert %{"status" => "completed", "warnings" => []} =
               json_response(response, 200)
    end

    test "grants past tier and event capacity, returning warnings", %{
      conn: conn
    } do
      Ysc.Ledgers.ensure_basic_accounts()
      member = member_with_active_membership()
      event = event_fixture(%{max_attendees: 1})
      tier = ticket_tier_fixture(%{event_id: event.id, quantity: 2})

      response =
        post(conn, ~p"/api/v1/app/events/#{event.id}/tickets/offline_order", %{
          "member_id" => member.id,
          "tiers" => %{tier.id => 5}
        })

      assert %{
               "status" => "completed",
               "ticket_count" => 5,
               "warnings" => warnings
             } =
               json_response(response, 200)

      assert length(warnings) == 2
    end
  end
end
