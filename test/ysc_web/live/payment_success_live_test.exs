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

      # Create a simple test module that returns appropriate payment intent
      test_stripe_client = fn _payment_intent_id, _metadata ->
        {:module, name, _, _} =
          defmodule :"TestStripeClient#{System.unique_integer()}" do
            @behaviour Ysc.StripeBehaviour

            def create_payment_intent(_params, _opts),
              do: {:error, :not_implemented}

            def retrieve_payment_intent(id, _opts) do
              metadata = Process.get(:test_metadata, %{})

              payment_intent = %Stripe.PaymentIntent{
                id: id,
                metadata: metadata,
                status: Process.get(:test_status, "succeeded")
              }

              {:ok, payment_intent}
            end

            def cancel_payment_intent(_id, _opts),
              do: {:error, :not_implemented}

            def create_customer(_params), do: {:error, :not_implemented}
            def update_customer(_id, _params), do: {:error, :not_implemented}
            def retrieve_payment_method(_id), do: {:error, :not_implemented}
          end

        name
      end

      conn = log_in_user(conn, user)

      %{
        conn: conn,
        user: user,
        booking: booking,
        test_stripe_client: test_stripe_client
      }
    end

    test "redirects to booking receipt with confetti", %{
      conn: conn,
      booking: booking,
      test_stripe_client: test_stripe_client
    } do
      payment_intent_id = "pi_test_123"

      client_module =
        test_stripe_client.(payment_intent_id, %{"booking_id" => booking.id})

      # Set test data in process dictionary for the test client
      Process.put(:test_metadata, %{"booking_id" => booking.id})

      # Override stripe client config
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
        Process.delete(:test_metadata)
      end
    end

    test "extracts payment intent from client secret format", %{
      conn: conn,
      booking: booking,
      test_stripe_client: test_stripe_client
    } do
      payment_intent_id = "pi_test_456"
      client_secret = "#{payment_intent_id}_secret_abc123"

      client_module =
        test_stripe_client.(payment_intent_id, %{"booking_id" => booking.id})

      Process.put(:test_metadata, %{"booking_id" => booking.id})
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
        Process.delete(:test_metadata)
      end
    end
  end

  describe "mount/3 - security and authorization" do
    test "prevents access to other user's booking", %{conn: conn} do
      user1 = user_fixture()
      user2 = user_fixture()
      booking = booking_fixture(%{user_id: user2.id})

      payment_intent_id = "pi_test_unauthorized"

      # Create test client
      {:module, client_module, _, _} =
        defmodule :"TestStripeClient#{System.unique_integer()}" do
          @behaviour Ysc.StripeBehaviour

          def create_payment_intent(_params, _opts),
            do: {:error, :not_implemented}

          def retrieve_payment_intent(id, _opts) do
            {:ok,
             %Stripe.PaymentIntent{
               id: id,
               metadata: Process.get(:test_metadata, %{})
             }}
          end

          def cancel_payment_intent(_id, _opts), do: {:error, :not_implemented}
          def create_customer(_params), do: {:error, :not_implemented}
          def update_customer(_id, _params), do: {:error, :not_implemented}
          def retrieve_payment_method(_id), do: {:error, :not_implemented}
        end

      Process.put(:test_metadata, %{"booking_id" => booking.id})
      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        assert {:error, {:redirect, %{to: "/", flash: flash}}} =
                 conn
                 |> log_in_user(user1)
                 |> live(
                   ~p"/payment/success?redirect_status=succeeded&payment_intent=#{payment_intent_id}"
                 )

        assert flash["error"] =~
                 "Payment was successful, but we couldn't find your booking or order"
      after
        Application.put_env(:ysc, :stripe_client, original_client)
        Process.delete(:test_metadata)
      end
    end
  end

  describe "mount/3 - failed and canceled payments" do
    setup %{conn: conn} do
      user = user_fixture()
      booking = booking_fixture(%{user_id: user.id})

      {:module, client_module, _, _} =
        defmodule :"TestStripeClient#{System.unique_integer()}" do
          @behaviour Ysc.StripeBehaviour

          def create_payment_intent(_params, _opts),
            do: {:error, :not_implemented}

          def retrieve_payment_intent(id, _opts) do
            {:ok,
             %Stripe.PaymentIntent{
               id: id,
               metadata: Process.get(:test_metadata, %{}),
               status: Process.get(:test_status, "failed")
             }}
          end

          def cancel_payment_intent(_id, _opts), do: {:error, :not_implemented}
          def create_customer(_params), do: {:error, :not_implemented}
          def update_customer(_id, _params), do: {:error, :not_implemented}
          def retrieve_payment_method(_id), do: {:error, :not_implemented}
        end

      conn = log_in_user(conn, user)

      %{conn: conn, user: user, booking: booking, client_module: client_module}
    end

    test "redirects to booking checkout on failed payment", %{
      conn: conn,
      booking: booking,
      client_module: client_module
    } do
      payment_intent_id = "pi_test_failed"

      Process.put(:test_metadata, %{"booking_id" => booking.id})
      Process.put(:test_status, "failed")
      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        assert {:error, {:redirect, %{to: redirect_path, flash: flash}}} =
                 live(
                   conn,
                   ~p"/payment/success?redirect_status=failed&payment_intent=#{payment_intent_id}"
                 )

        assert redirect_path == "/bookings/checkout/#{booking.id}"
        assert flash["error"] =~ "Payment failed"
      after
        Application.put_env(:ysc, :stripe_client, original_client)
        Process.delete(:test_metadata)
        Process.delete(:test_status)
      end
    end

    test "redirects to booking checkout on canceled payment", %{
      conn: conn,
      booking: booking,
      client_module: client_module
    } do
      payment_intent_id = "pi_test_canceled"

      Process.put(:test_metadata, %{"booking_id" => booking.id})
      Process.put(:test_status, "canceled")
      original_client = Application.get_env(:ysc, :stripe_client)
      Application.put_env(:ysc, :stripe_client, client_module)

      try do
        assert {:error, {:redirect, %{to: redirect_path, flash: flash}}} =
                 live(
                   conn,
                   ~p"/payment/success?redirect_status=canceled&payment_intent=#{payment_intent_id}"
                 )

        assert redirect_path == "/bookings/checkout/#{booking.id}"
        assert flash["error"] =~ "Payment was canceled"
      after
        Application.put_env(:ysc, :stripe_client, original_client)
        Process.delete(:test_metadata)
        Process.delete(:test_status)
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

      assert flash["error"] == "Invalid payment information."
    end

    test "handles missing redirect_status parameter", %{conn: conn} do
      user = user_fixture()

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn
               |> log_in_user(user)
               |> live(~p"/payment/success?payment_intent=pi_test")

      assert flash["error"] ==
               "Payment status is unclear. Please check your booking or order status."
    end
  end

  describe "render/1" do
    test "renders processing message (should never be seen in practice)" do
      # This tests the render function directly, though in practice it should
      # never render because mount always redirects
      user = user_fixture()

      assigns = %{
        current_user: user,
        flash: %{},
        live_action: nil
      }

      html = YscWeb.PaymentSuccessLive.render(assigns)
      html_string = Phoenix.HTML.Safe.to_iodata(html) |> IO.iodata_to_binary()

      assert html_string =~ "Processing your payment"
    end
  end
end
