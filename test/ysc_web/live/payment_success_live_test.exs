defmodule YscWeb.PaymentSuccessLiveTest do
  @moduledoc """
  Tests for PaymentSuccessLive.

  This LiveView handles Stripe payment redirects for external payment methods.
  It processes success and failure callbacks, retrieves payment intents from Stripe,
  and redirects to appropriate pages based on payment status and metadata.

  ## Test Coverage

  - Mount scenarios (authenticated, unauthenticated)
  - Successful payments (booking, ticket order)
  - Failed/canceled payments
  - Payment intent extraction (different formats)
  - Error handling (missing parameters)
  - Security: unauthorized access attempts
  """
  use YscWeb.ConnCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.Tickets

  describe "mount/3 - authentication" do
    test "redirects unauthenticated users to home with error", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/payment/success?redirect_status=succeeded")

      assert flash["error"] == "You must be signed in to view this page."
    end
  end

  describe "mount/3 - successful payment with booking" do
    setup %{conn: conn} do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      %{
        conn: conn,
        user: user,
        booking: booking
      }
    end

    test "redirects to booking receipt with confetti", %{
      conn: conn,
      booking: booking
    } do
      payment_intent_id = "pi_test_123"
      client_module = stripe_client_module(%{"booking_id" => booking.id})
      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        assert {:error, {:redirect, %{to: redirect_path}}} =
                 live(
                   conn,
                   ~p"/payment/success?redirect_status=succeeded&payment_intent=#{payment_intent_id}"
                 )

        assert redirect_path == "/bookings/#{booking.id}/receipt?confetti=true"
      after
        Application.put_env(:ysc, :stripe_client, original_client)
      end
    end

    test "extracts payment intent from client secret format", %{
      conn: conn,
      booking: booking
    } do
      payment_intent_id = "pi_test_456"
      client_secret = "#{payment_intent_id}_secret_abc123"
      client_module = stripe_client_module(%{"booking_id" => booking.id})
      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        assert {:error, {:redirect, %{to: redirect_path}}} =
                 live(
                   conn,
                   ~p"/payment/success?redirect_status=succeeded&payment_intent_client_secret=#{client_secret}"
                 )

        assert redirect_path == "/bookings/#{booking.id}/receipt?confetti=true"
      after
        Application.put_env(:ysc, :stripe_client, original_client)
      end
    end
  end

  describe "mount/3 - successful payment with ticket order" do
    setup %{conn: conn} do
      Ysc.Ledgers.ensure_basic_accounts()

      user =
        user_fixture()
        |> Ecto.Changeset.change(%{
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      {:ok, event} =
        Ysc.Events.create_event(%{
          title: "Payment success event #{System.unique_integer()}",
          description: "Test",
          state: :published,
          organizer_id: user_fixture().id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          max_attendees: 100,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 50,
          event_id: event.id
        })

      {:ok, order} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})
        end)

      cancel_timeout_jobs_for_order!(order.id)

      order =
        order
        |> Ecto.Changeset.change(
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(1, :hour)
            |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      %{
        conn: log_in_user(conn, user),
        user: user,
        event: event,
        order: order
      }
    end

    test "redirects to order confirmation with confetti", %{
      conn: conn,
      user: user,
      order: order
    } do
      payment_intent_id = "pi_ticket_success_#{order.id}"

      client_module =
        stripe_client_module(
          %{"ticket_order_id" => order.id, "user_id" => user.id},
          amount_cents: 5000
        )

      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        assert {:error, {:redirect, %{to: redirect_path}}} =
                 live(
                   conn,
                   ~p"/payment/success?redirect_status=succeeded&payment_intent=#{payment_intent_id}"
                 )

        assert redirect_path ==
                 "/orders/#{order.id}/confirmation?confetti=true"
      after
        Application.put_env(:ysc, :stripe_client, original_client)
      end
    end

    test "completes pending ticket order after redirect payment", %{
      conn: conn,
      user: user,
      order: order
    } do
      payment_intent_id = "pi_ticket_complete_#{order.id}"
      pending_order = Repo.get!(Ysc.Tickets.TicketOrder, order.id)
      assert pending_order.status == :pending

      client_module =
        stripe_client_module(
          %{"ticket_order_id" => order.id, "user_id" => user.id},
          amount_cents: 5000
        )

      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        assert {:error, {:redirect, _}} =
                 live(
                   conn,
                   ~p"/payment/success?redirect_status=succeeded&payment_intent=#{payment_intent_id}"
                 )

        completed = Repo.get!(Ysc.Tickets.TicketOrder, order.id)
        assert completed.status == :completed
        assert completed.payment_id

        assert Enum.all?(
                 Repo.all(
                   from t in Ysc.Events.Ticket,
                     where: t.ticket_order_id == ^order.id
                 ),
                 &(&1.status == :confirmed)
               )
      after
        Application.put_env(:ysc, :stripe_client, original_client)
      end
    end
  end

  describe "mount/3 - security and authorization" do
    test "prevents access to other user's booking", %{conn: conn} do
      Logger.put_module_level(YscWeb.PaymentSuccessLive, :none)

      user1 = user_fixture()
      user2 = user_fixture()
      booking = booking_fixture(%{user_id: user2.id})

      payment_intent_id = "pi_test_unauthorized"
      client_module = stripe_client_module(%{"booking_id" => booking.id})
      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        redirect =
          conn
          |> log_in_user(user1)
          |> live(
            ~p"/payment/success?redirect_status=succeeded&payment_intent=#{payment_intent_id}"
          )

        {:ok, conn} = follow_redirect(redirect, conn)

        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
                 "Your payment went through, but we couldn't load your confirmation"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
                 Ysc.EmailConfig.contact_email()
      after
        Logger.put_module_level(YscWeb.PaymentSuccessLive, :error)
        Application.put_env(:ysc, :stripe_client, original_client)
      end
    end

    test "prevents redirect to another user's ticket order", %{conn: conn} do
      Logger.put_module_level(YscWeb.PaymentSuccessLive, :none)

      owner =
        user_fixture()
        |> Ecto.Changeset.change(%{
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      {:ok, event} =
        Ysc.Events.create_event(%{
          title: "Unauthorized ticket order event",
          description: "Test",
          state: :published,
          organizer_id: user_fixture().id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          max_attendees: 100,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 50,
          event_id: event.id
        })

      {:ok, order} =
        Tickets.create_ticket_order(owner.id, event.id, %{tier.id => 1})

      payment_intent_id = "pi_ticket_unauthorized_#{order.id}"
      client_module = stripe_client_module(%{"ticket_order_id" => order.id})
      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        redirect =
          conn
          |> log_in_user(user_fixture())
          |> live(
            ~p"/payment/success?redirect_status=succeeded&payment_intent=#{payment_intent_id}"
          )

        {:ok, conn} = follow_redirect(redirect, conn)

        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
                 "Your payment went through, but we couldn't load your confirmation"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
                 Ysc.EmailConfig.contact_email()
      after
        Logger.put_module_level(YscWeb.PaymentSuccessLive, :error)
        Application.put_env(:ysc, :stripe_client, original_client)
      end
    end
  end

  describe "mount/3 - failed and canceled payments" do
    setup %{conn: conn} do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      %{conn: conn, user: user, booking: booking}
    end

    test "redirects to booking checkout on failed payment", %{
      conn: conn,
      booking: booking
    } do
      payment_intent_id = "pi_test_failed"

      client_module =
        stripe_client_module(%{"booking_id" => booking.id}, status: "failed")

      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        redirect =
          live(
            conn,
            ~p"/payment/success?redirect_status=failed&payment_intent=#{payment_intent_id}"
          )

        {:ok, conn} = follow_redirect(redirect, conn)

        assert conn.request_path == "/bookings/checkout/#{booking.id}"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Payment failed"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "info@ysc.org"
      after
        Application.put_env(:ysc, :stripe_client, original_client)
      end
    end

    test "redirects to booking checkout on canceled payment", %{
      conn: conn,
      booking: booking
    } do
      payment_intent_id = "pi_test_canceled"

      client_module =
        stripe_client_module(%{"booking_id" => booking.id}, status: "canceled")

      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        redirect =
          live(
            conn,
            ~p"/payment/success?redirect_status=canceled&payment_intent=#{payment_intent_id}"
          )

        {:ok, conn} = follow_redirect(redirect, conn)

        assert conn.request_path == "/bookings/checkout/#{booking.id}"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
                 "Payment was canceled"
      after
        Application.put_env(:ysc, :stripe_client, original_client)
      end
    end

    test "redirects to event page on failed ticket order payment", %{conn: conn} do
      user =
        user_fixture()
        |> Ecto.Changeset.change(%{
          lifetime_membership_awarded_at:
            DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()

      {:ok, event} =
        Ysc.Events.create_event(%{
          title: "Failed payment event #{System.unique_integer()}",
          description: "Test",
          state: :published,
          organizer_id: user_fixture().id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          max_attendees: 100,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, tier} =
        Ysc.Events.create_ticket_tier(%{
          name: "GA",
          type: :paid,
          price: Money.new(50, :USD),
          quantity: 50,
          event_id: event.id
        })

      {:ok, order} =
        Tickets.create_ticket_order(user.id, event.id, %{tier.id => 1})

      payment_intent_id = "pi_ticket_failed_#{order.id}"

      client_module =
        stripe_client_module(%{"ticket_order_id" => order.id}, status: "failed")

      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        redirect =
          conn
          |> log_in_user(user)
          |> live(
            ~p"/payment/success?redirect_status=failed&payment_intent=#{payment_intent_id}"
          )

        {:ok, conn} = follow_redirect(redirect, conn)

        assert conn.request_path == "/events/#{event.id}"
        assert conn.query_params["payment_failed"] == "1"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Payment failed"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "info@ysc.org"
        assert Repo.get!(Ysc.Tickets.TicketOrder, order.id).status == :cancelled
      after
        Application.put_env(:ysc, :stripe_client, original_client)
      end
    end
  end

  describe "mount/3 - error handling" do
    test "handles missing payment intent parameter", %{conn: conn} do
      user = user_fixture()

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn
               |> log_in_user(user)
               |> live(~p"/payment/success?redirect_status=succeeded")

      assert flash["error"] =~ "We couldn't confirm your payment from this link"
    end

    test "handles missing redirect_status parameter", %{conn: conn} do
      user = user_fixture()

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn
               |> log_in_user(user)
               |> live(~p"/payment/success?payment_intent=pi_test")

      assert flash["error"] =~
               "We couldn't confirm your payment from this link. Click your name in the top-right corner and open My Bookings & Payments"
    end
  end

  describe "render/1" do
    test "renders processing message while payment redirect is pending" do
      user = user_fixture()

      assigns = %{
        current_user: user,
        flash: %{},
        live_action: nil,
        processing_payment?: true
      }

      html = YscWeb.PaymentSuccessLive.render(assigns)
      html_string = Phoenix.HTML.Safe.to_iodata(html) |> IO.iodata_to_binary()

      assert html_string =~ "Processing your payment"
    end
  end

  defp cancel_timeout_jobs_for_order!(ticket_order_id) do
    import Ecto.Query

    from(j in Oban.Job,
      where: j.worker == "Ysc.Tickets.TimeoutWorker",
      where: fragment("?->>'ticket_order_id' = ?", j.args, ^ticket_order_id),
      where: j.state in ["available", "scheduled", "retryable"]
    )
    |> Repo.delete_all()
  end

  defp stripe_client_module(metadata, opts \\ []) do
    status = Keyword.get(opts, :status, "succeeded")
    amount_cents = Keyword.get(opts, :amount_cents)
    unique = System.unique_integer([:positive])
    module_name = Module.concat(__MODULE__, :"StripeClient#{unique}")

    Module.create(
      module_name,
      quote do
        @behaviour Ysc.StripeBehaviour
        @metadata unquote(Macro.escape(metadata))
        @status unquote(status)
        @amount_cents unquote(amount_cents)

        def create_payment_intent(_params, _opts),
          do: {:error, :not_implemented}

        def cancel_payment_intent(_id, _opts), do: {:error, :not_implemented}
        def create_customer(_params), do: {:error, :not_implemented}
        def update_customer(_id, _params), do: {:error, :not_implemented}
        def retrieve_payment_method(_id), do: {:error, :not_implemented}

        def retrieve_payment_intent(id, _opts) do
          payment_intent = %Stripe.PaymentIntent{
            id: id,
            metadata: @metadata,
            status: @status
          }

          payment_intent =
            case @amount_cents do
              nil -> payment_intent
              amount -> %{payment_intent | amount: amount}
            end

          {:ok, payment_intent}
        end
      end,
      Macro.Env.location(__ENV__)
    )

    module_name
  end
end
