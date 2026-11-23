defmodule YscWeb.GuestCheckoutLiveTest do
  @moduledoc """
  Guest checkout page: buying public-sale tickets with just a name and email.
  """
  use YscWeb.ConnCase, async: false

  import Ecto.Query
  import Mox
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures
  import EventDetailsLiveHelpers

  alias Ysc.Events
  alias Ysc.Tickets.AccessToken
  alias Ysc.Tickets.GuestCheckout
  alias Ysc.Tickets.TicketOrder

  setup :verify_on_exit!

  setup %{conn: conn} do
    setup_stripe_mocks()
    original_stripe_client = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      {:ok,
       build_payment_intent(%{
         id: "pi_guest_#{System.unique_integer([:positive])}",
         amount: params.amount,
         metadata: params.metadata
       })}
    end)

    organizer = user_fixture()

    {:ok, event} =
      Events.create_event(%{
        title: "Guest Event #{System.unique_integer([:positive])}",
        description: "Open to all",
        state: :published,
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 50,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    tier = fn name, attrs ->
      {:ok, tier} =
        Events.create_ticket_tier(
          Map.merge(
            %{
              name: name,
              type: :paid,
              price: Money.new(30, :USD),
              quantity: 20,
              event_id: event.id
            },
            attrs
          )
        )

      tier
    end

    %{
      conn: conn,
      event: event,
      public_tier: tier.("Public GA", %{sale_audience: :public}),
      free_tier:
        tier.("Public free", %{
          sale_audience: :public,
          type: :free,
          price: Money.new(0, :USD)
        }),
      member_tier: tier.("Members", %{sale_audience: :member_guests})
    }
  end

  defp checkout_path(event, selections) do
    token = GuestCheckout.sign_selection(event.id, selections)
    ~p"/events/#{event.id}/checkout?s=#{token}"
  end

  defp submit_details(view, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          "first_name" => "Gus",
          "last_name" => "Buyer",
          "email" => "gus@example.com"
        },
        attrs
      )

    view
    |> form("#guest-checkout-form", guest: params)
    |> render_submit(%{"cf-turnstile-response" => "ok"})
  end

  describe "picker hands over to guest checkout" do
    test "anonymous checkout of a public tier opens the guest page", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}/tickets")
      render_async(view)
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier.id})
      render_click(view, "proceed-to-checkout")

      {path, _flash} = assert_redirect(view)
      assert path =~ "/events/#{event.id}/checkout?s="
    end
  end

  describe "details step" do
    test "shows the summary and form", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 2}))

      assert has_element?(view, "#guest-checkout-form")
      assert has_element?(view, "#guest-checkout-summary", "Public GA")
      assert has_element?(view, "#guest-checkout-total", "$60.00")
      assert has_element?(view, "#guest-checkout-sign-in")
    end

    test "a bad or missing token goes back to the event", %{
      conn: conn,
      event: event
    } do
      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/events/#{event.id}/checkout?s=nope")

      assert to == "/events/#{event.id}"

      assert {:error, {:live_redirect, %{to: ^to}}} =
               live(conn, ~p"/events/#{event.id}/checkout")
    end

    test "member tiers are refused", %{
      conn: conn,
      event: event,
      member_tier: tier
    } do
      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, checkout_path(event, %{tier.id => 1}))

      assert to == "/events/#{event.id}"
    end

    test "signed-in visitors use the regular checkout", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      conn = log_in_user(conn, user_fixture())

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, checkout_path(event, %{tier.id => 1}))

      assert to == "/events/#{event.id}/tickets"
    end

    test "signed-in visitors skip the event SELECT", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      conn = log_in_user(conn, user_fixture())

      {result, event_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> live(conn, checkout_path(event, %{tier.id => 1})) end,
          pattern: ~r/FROM "events"/i,
          caller_pids: [self()]
        )

      assert {:error, {:live_redirect, %{to: to}}} = result
      assert to == "/events/#{event.id}/tickets"
      assert event_cols == 0
    end

    test "dead render omits event-body columns and the empty reservation join",
         %{
           conn: conn,
           event: event,
           public_tier: tier
         } do
      path = checkout_path(event, %{tier.id => 2})

      {{:ok, view, _html}, body_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> live(conn, path) end,
          pattern: ~r/raw_details|rendered_details/i,
          caller_pids: [self()]
        )

      {_, reservation_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> live(conn, path) end,
          pattern: ~r/FROM "ticket_reservations"/i,
          caller_pids: [self()]
        )

      {_, tier_cols} =
        Ysc.QueryCounter.with_query_counter(
          fn -> live(conn, path) end,
          pattern: ~r/FROM "ticket_tiers"/i,
          caller_pids: [self()]
        )

      assert has_element?(view, "#guest-checkout-form")
      assert body_cols == 0
      assert reservation_cols == 0
      assert tier_cols == 1
    end

    test "a missing or draft event goes back to the events list", %{
      conn: conn
    } do
      assert {:error, {:live_redirect, %{to: "/events"}}} =
               live(conn, ~p"/events/#{Ecto.ULID.generate()}/checkout?s=nope")

      draft =
        event_fixture(%{
          title: "Draft guest checkout",
          state: :draft,
          published_at: nil
        })

      assert {:error, {:live_redirect, %{to: "/events"}}} =
               live(conn, checkout_path(draft, %{Ecto.ULID.generate() => 1}))
    end

    test "invalid contact details keep the form and create no order", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 1}))

      submit_details(view, %{"email" => "not-an-email"})

      assert has_element?(view, "#guest-checkout-form")
      refute has_element?(view, "#payment-element")
      assert Ysc.Repo.aggregate(TicketOrder, :count) == 0
    end
  end

  describe "payment step" do
    test "valid details hold the tickets and show the payment form", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 2}))

      submit_details(view)

      assert has_element?(view, "#payment-element[phx-hook='StripeElements']")
      assert has_element?(view, "#guest-checkout-hold", "gus@example.com")
      refute has_element?(view, "#guest-checkout-form")

      assert %TicketOrder{
               user_id: nil,
               guest_email: "gus@example.com",
               status: :pending
             } =
               Ysc.Repo.one!(TicketOrder)

      assert has_element?(
               view,
               ~s(#payment-element[data-return-path="/events/#{event.id}/checkout/return"])
             )
    end

    test "cancel releases the held tickets", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 1}))
      submit_details(view)

      # The order carries its saved PaymentIntent, so cancelling consults and
      # cancels it at Stripe.
      stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
        {:ok,
         build_payment_intent(%{id: id, status: "requires_payment_method"})}
      end)

      stub(Ysc.StripeMock, :cancel_payment_intent, fn id, _opts ->
        {:ok, build_payment_intent(%{id: id, status: "canceled"})}
      end)

      render_click(view, "cancel")
      assert_redirect(view, ~p"/events/#{event.id}")

      assert Ysc.Repo.one!(TicketOrder).status in [:cancelled, :expired]
    end

    test "a free selection skips payment and opens the tickets", %{
      conn: conn,
      event: event,
      free_tier: tier
    } do
      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 1}))

      submit_details(view)

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r{^/t/[^/]+/confirmation\?confetti=true$}
      assert Ysc.Repo.one!(TicketOrder).status == :completed
    end

    test "payment success completes the order and opens the tickets", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 1}))
      submit_details(view)

      order = Ysc.Repo.one!(TicketOrder)
      pi_id = "pi_paid_#{System.unique_integer([:positive])}"

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn ^pi_id, _opts ->
        {:ok,
         build_payment_intent(%{
           id: pi_id,
           status: "succeeded",
           amount: 3000,
           metadata: %{
             "ticket_order_id" => order.id,
             "ticket_order_reference" => order.reference_id,
             "event_id" => event.id
           }
         })}
      end)

      render_hook(view, "payment-success", %{"payment_intent_id" => pi_id})

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r{^/t/[^/]+/confirmation\?confetti=true$}
      assert Ysc.Repo.get!(TicketOrder, order.id).status == :completed
    end
  end

  describe "amount shown at payment" do
    test "a price change after the page loaded shows the charged total and matching lines",
         %{conn: conn, event: event, public_tier: tier} do
      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 1}))
      assert has_element?(view, "#guest-checkout-total", "$30.00")

      {:ok, _} = Events.update_ticket_tier(tier, %{price: Money.new(35, :USD)})

      submit_details(view)

      assert has_element?(view, "#guest-checkout-total", "$35.00")
      assert has_element?(view, "#guest-line-price-#{tier.id}", "$35.00")
    end

    test "line prices are hidden when the reloaded prices don't add up to the charge",
         %{conn: conn, event: event, public_tier: tier} do
      # The price moves again after payment setup priced the order, before the
      # summary reloads the tiers.
      stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
        {:ok, _} =
          Events.update_ticket_tier(tier, %{price: Money.new(40, :USD)})

        {:ok, build_payment_intent(%{id: "pi_moved", amount: params.amount})}
      end)

      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 1}))
      submit_details(view)

      assert has_element?(view, "#guest-checkout-total", "$30.00")
      refute has_element?(view, "#guest-line-price-#{tier.id}")
    end
  end

  describe "hold expiry" do
    defp start_payment(conn, event, tier) do
      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 1}))
      submit_details(view)
      {view, Ysc.Repo.one!(TicketOrder)}
    end

    test "releases the tickets when Stripe confirms nothing was paid", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      {view, order} = start_payment(conn, event, tier)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
        {:ok,
         build_payment_intent(%{id: id, status: "requires_payment_method"})}
      end)

      stub(Ysc.StripeMock, :cancel_payment_intent, fn id, _opts ->
        {:ok, build_payment_intent(%{id: id, status: "canceled"})}
      end)

      send(view.pid, :hold_expired)

      assert_redirect(view, ~p"/events/#{event.id}")

      assert Ysc.Repo.get!(TicketOrder, order.id).status in [
               :expired,
               :cancelled
             ]
    end

    test "opens the tickets when the payment had already succeeded", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      {view, order} = start_payment(conn, event, tier)

      # The card was charged, but the browser never reported it. Stripe
      # refuses to cancel a succeeded intent and reports it as succeeded.
      stub(Ysc.StripeMock, :cancel_payment_intent, fn _id, _opts ->
        {:error,
         %Stripe.Error{
           message: "already succeeded",
           source: :api,
           code: "payment_intent_unexpected_state"
         }}
      end)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
        {:ok,
         build_payment_intent(%{
           id: id,
           status: "succeeded",
           amount: 3000,
           metadata: %{
             "ticket_order_id" => order.id,
             "ticket_order_reference" => order.reference_id,
             "event_id" => event.id
           }
         })}
      end)

      send(view.pid, :hold_expired)

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r{^/t/[^/]+/confirmation\?confetti=true$}
      assert Ysc.Repo.get!(TicketOrder, order.id).status == :completed
    end

    test "leaves the order alone and says so while a payment is processing", %{
      conn: conn,
      event: event,
      public_tier: tier
    } do
      {view, order} = start_payment(conn, event, tier)

      # Stripe refuses to cancel an intent that is processing, then reports it so.
      stub(Ysc.StripeMock, :cancel_payment_intent, fn _id, _opts ->
        {:error,
         %Stripe.Error{
           message: "cannot cancel",
           source: :api,
           code: "payment_intent_unexpected_state"
         }}
      end)

      stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, _opts ->
        {:ok,
         build_payment_intent(%{id: id, status: "processing", amount: 3000})}
      end)

      send(view.pid, :hold_expired)
      render(view)

      assert Ysc.Repo.get!(TicketOrder, order.id).status == :pending
      assert has_element?(view, "#payment-element")
    end
  end

  describe "return route" do
    test "a failed redirect payment goes back to the event", %{
      conn: conn,
      event: event
    } do
      assert {:error, {:live_redirect, %{to: to}}} =
               live(
                 conn,
                 ~p"/events/#{event.id}/checkout/return?redirect_status=failed&payment_intent=pi_x"
               )

      assert to == "/events/#{event.id}"
    end

    test "an unknown payment intent cannot open tickets", %{
      conn: conn,
      event: event
    } do
      stub(Ysc.StripeMock, :retrieve_payment_intent, fn _id, _opts ->
        {:ok,
         build_payment_intent(%{id: "pi_other", client_secret: "real_secret"})}
      end)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(
                 conn,
                 ~p"/events/#{event.id}/checkout/return?redirect_status=succeeded&payment_intent=pi_other&payment_intent_client_secret=wrong"
               )

      assert path == "/events/#{event.id}"
      assert Ysc.Repo.aggregate(from(o in TicketOrder), :count) == 0
    end
  end

  describe "order confirmation" do
    defp completed_guest_order(event, tier) do
      guest = %{
        email: "gus@example.com",
        first_name: "Gus",
        last_name: "Buyer"
      }

      {:ok, order} =
        GuestCheckout.create_order(guest, event.id, %{tier.id => 2})

      {:ok, completed} = Ysc.Tickets.process_free_ticket_order(order)
      completed
    end

    defp confirmation_path(order),
      do: ~p"/t/#{AccessToken.sign_order(order.id)}/confirmation"

    test "a finished checkout lands on the confirmation page", %{
      conn: conn,
      event: event,
      free_tier: tier
    } do
      {:ok, view, _html} = live(conn, checkout_path(event, %{tier.id => 1}))
      submit_details(view)

      {path, _flash} = assert_redirect(view)
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "#order-confirmation")
      assert has_element?(view, "#order-confirmation-header", "Gus")

      assert has_element?(
               view,
               "#order-confirmation-guest-email",
               "gus@example.com"
             )

      assert has_element?(view, "#order-confirmation-event", event.title)
      assert has_element?(view, "#order-confirmation-total-amount", "Free")
    end

    test "points at the tickets by token and hides member-only links", %{
      conn: conn,
      event: event,
      free_tier: tier
    } do
      order = completed_guest_order(event, tier)
      token = AccessToken.sign_order(order.id)

      {:ok, view, _html} = live(conn, ~p"/t/#{token}/confirmation")

      for ticket <- Ysc.Repo.preload(order, :tickets).tickets do
        assert has_element?(view, "#order-confirmation-ticket-#{ticket.id}")
      end

      assert has_element?(
               view,
               ~s(#order-confirmation-checkin-qr[href="/t/#{token}"])
             )

      refute has_element?(view, "#order-confirmation-all-tickets")
    end

    test "a token for a different kind of access doesn't open it", %{
      conn: conn,
      event: event,
      free_tier: tier
    } do
      order = completed_guest_order(event, tier)
      [ticket | _] = Ysc.Repo.preload(order, :tickets).tickets

      assert {:error, {:redirect, %{to: "/events"}}} =
               live(
                 conn,
                 ~p"/t/#{AccessToken.sign_ticket(ticket.id)}/confirmation"
               )

      assert {:error, {:redirect, %{to: "/events"}}} =
               live(conn, ~p"/t/not-a-token/confirmation")
    end

    test "never shows an order placed by a member", %{conn: conn} do
      %{order: order} = Ysc.TicketAccessFixtures.granted_tickets(1)

      assert {:error, {:redirect, %{to: "/events"}}} =
               live(conn, confirmation_path(order))
    end

    test "an order that isn't confirmed yet sends the buyer to the ticket page",
         %{conn: conn, event: event, free_tier: tier} do
      {:ok, pending} =
        GuestCheckout.create_order(
          %{email: "gus@example.com", first_name: "Gus", last_name: "Buyer"},
          event.id,
          %{tier.id => 1}
        )

      token = AccessToken.sign_order(pending.id)

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/t/#{token}/confirmation")

      assert path == "/t/#{token}"
    end
  end
end
