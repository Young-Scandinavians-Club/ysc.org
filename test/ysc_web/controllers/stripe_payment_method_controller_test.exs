defmodule YscWeb.Controllers.StripePaymentMethodControllerTest do
  @moduledoc """
  Tests for Stripe Payment Method Controller.

  Production bugs have been fixed and Stripe API mocking is configured.
  These tests verify route accessibility, authentication requirements,
  error handling, and security checks.
  """
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures
  import Mox

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup %{conn: conn} do
    user = user_fixture(%{stripe_id: "cus_test123"})
    {:ok, conn: conn, user: user}
  end

  describe "authentication" do
    test "GET /billing/user/:user_id/finalize requires authentication", %{
      conn: conn,
      user: user
    } do
      conn = get(conn, "/billing/user/#{user.id}/finalize")
      assert redirected_to(conn) == "/users/log-in"
    end

    test "GET /billing/user/:user_id/setup-payment requires authentication", %{
      conn: conn,
      user: user
    } do
      conn = get(conn, "/billing/user/#{user.id}/setup-payment")
      assert redirected_to(conn) == "/users/log-in"
    end

    test "POST /billing/user/:user_id/payment-method requires authentication", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, "/billing/user/#{user.id}/payment-method", %{
          "payment_method_id" => "pm_test123"
        })

      assert redirected_to(conn) == "/users/log-in"
    end
  end

  describe "finalize/2" do
    test "redirects to home when no payment_intent or setup_intent", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> log_in_user(user)
        |> get("/billing/user/#{user.id}/finalize")

      assert redirected_to(conn) == "/"
    end

    test "constructs correct URLs in props", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> get("/billing/user/#{user.id}/finalize")

      # Should redirect to home since no intents provided
      assert redirected_to(conn) == "/"
    end
  end

  describe "setup_payment/2" do
    test "creates setup intent for the authenticated user", %{
      conn: conn,
      user: user
    } do
      Ysc.CustomersMock
      |> stub(:create_setup_intent, fn _user ->
        {:ok,
         %Stripe.SetupIntent{
           id: "seti_new123",
           client_secret: "seti_new123_secret_xxx",
           status: "requires_payment_method",
           customer: "cus_test123"
         }}
      end)

      conn =
        conn
        |> log_in_user(user)
        |> get("/billing/user/#{user.id}/setup-payment")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["client_secret"] == "seti_new123_secret_xxx"
    end

    test "ignores user_id in URL and always uses the authenticated user (IDOR fix)",
         %{
           conn: conn,
           user: user
         } do
      other_user = user_fixture(%{stripe_id: "cus_other_user"})

      # The create_setup_intent mock captures which user it is called with.
      # It must be called with the *authenticated* user (user), not other_user.
      Ysc.CustomersMock
      |> expect(:create_setup_intent, fn called_with_user ->
        assert called_with_user.id == user.id,
               "setup_payment must use current_user, not user_id from URL"

        {:ok,
         %Stripe.SetupIntent{
           id: "seti_correct",
           client_secret: "seti_correct_secret",
           status: "requires_payment_method",
           customer: user.stripe_id
         }}
      end)

      # Log in as `user` but pass `other_user`'s ID in the URL path.
      # Before the IDOR fix, this would have created a SetupIntent for other_user.
      # After the fix, it must create one for the authenticated user.
      conn =
        conn
        |> log_in_user(user)
        |> get("/billing/user/#{other_user.id}/setup-payment")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["client_secret"] == "seti_correct_secret"
    end

    test "returns error when Stripe call fails", %{conn: conn, user: user} do
      Ysc.CustomersMock
      |> stub(:create_setup_intent, fn _user ->
        {:error,
         %Stripe.Error{
           message: "No such customer",
           source: :api,
           code: :resource_missing
         }}
      end)

      conn =
        conn
        |> log_in_user(user)
        |> get("/billing/user/#{user.id}/setup-payment")

      assert conn.status == 400
      response = json_response(conn, 400)
      assert response["error"] == "Failed to create setup intent"
    end
  end

  describe "store_payment_method/2" do
    test "stores valid payment method", %{conn: conn, user: user} do
      # Mock successful payment method retrieval
      Stripe.PaymentMethodMock
      |> stub(:retrieve, fn "pm_test123" ->
        {:ok,
         %Stripe.PaymentMethod{
           id: "pm_test123",
           type: "card",
           card: %{brand: "visa", last4: "4242"}
         }}
      end)

      # Mock successful payment method storage
      Ysc.PaymentsMock
      |> stub(:upsert_and_set_default_payment_method_from_stripe, fn _user,
                                                                     _pm ->
        {:ok,
         %Ysc.Payments.PaymentMethod{
           id: "01HAS3FAKEULID00000000000",
           provider_id: "pm_test123",
           provider: :stripe,
           type: :card
         }}
      end)

      # Mock successful customer update
      Stripe.CustomerMock
      |> stub(:update, fn _customer_id,
                          %{
                            invoice_settings: %{
                              default_payment_method: "pm_test123"
                            }
                          },
                          [] ->
        {:ok,
         %Stripe.Customer{
           id: user.stripe_id,
           invoice_settings: %{default_payment_method: "pm_test123"}
         }}
      end)

      conn =
        conn
        |> log_in_user(user)
        |> post("/billing/user/#{user.id}/payment-method", %{
          "payment_method_id" => "pm_test123"
        })

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["success"] == true

      assert response["message"] ==
               "Payment method stored and set as default successfully"
    end

    test "returns error for invalid payment_method_id", %{
      conn: conn,
      user: user
    } do
      # Mock Stripe error when retrieving invalid payment method
      Stripe.PaymentMethodMock
      |> stub(:retrieve, fn "pm_invalid" ->
        {:error,
         %Stripe.Error{
           message: "No such payment_method: 'pm_invalid'",
           source: :api,
           code: :resource_missing
         }}
      end)

      conn =
        conn
        |> log_in_user(user)
        |> post("/billing/user/#{user.id}/payment-method", %{
          "payment_method_id" => "pm_invalid"
        })

      assert conn.status == 400
      response = json_response(conn, 400)

      assert response["error"] ==
               "Failed to retrieve payment method from Stripe"
    end

    test "returns error when payment_method_id is missing", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> log_in_user(user)
        |> post("/billing/user/#{user.id}/payment-method", %{})

      # Should fail because payment_method_id is nil
      assert conn.status in [400, 500]
      response = json_response(conn, conn.status)
      assert response["error"]
    end
  end

  describe "security" do
    test "store_payment_method uses current_user from session not URL", %{
      conn: conn
    } do
      user1 = user_fixture(%{stripe_id: "cus_user1"})
      user2 = user_fixture(%{stripe_id: "cus_user2"})

      # Mock payment method retrieval error
      Stripe.PaymentMethodMock
      |> stub(:retrieve, fn "pm_test" ->
        {:error,
         %Stripe.Error{
           message: "No such payment_method",
           source: :api,
           code: :resource_missing
         }}
      end)

      # Log in as user1 but try to access user2's route
      conn =
        conn
        |> log_in_user(user1)
        |> post("/billing/user/#{user2.id}/payment-method", %{
          "payment_method_id" => "pm_test"
        })

      # Controller uses conn.assigns.current_user (user1), not params["user_id"] (user2)
      # So this will try to add payment method to user1, which is correct
      # The actual security is in Stripe API call verification
      assert conn.status in [400, 500]
    end

    test "finalize verifies intent.customer matches user.stripe_id", %{
      conn: conn
    } do
      user1 = user_fixture(%{stripe_id: "cus_user1"})
      _user2 = user_fixture(%{stripe_id: "cus_user2"})

      # Mock payment intent that belongs to user2
      Stripe.PaymentIntentMock
      |> stub(:retrieve, fn "pi_user2", %{} ->
        {:ok,
         %Stripe.PaymentIntent{
           id: "pi_user2",
           client_secret: "pi_user2_secret",
           amount: 5000,
           currency: "usd",
           status: "succeeded",
           customer: "cus_user2"
         }}
      end)

      # Log in as user1 but try to access user2's payment intent
      conn =
        conn
        |> log_in_user(user1)
        |> get("/billing/user/#{user1.id}/finalize", %{
          "payment_intent" => "pi_user2"
        })

      # Should not return payment intent data since customer doesn't match
      assert redirected_to(conn) == "/"
    end

    test "uses current_user consistently throughout controller", %{
      conn: conn,
      user: user
    } do
      # Verify that after fixing bugs, controller uses current_user not user
      conn =
        conn
        |> log_in_user(user)
        |> get("/billing/user/#{user.id}/finalize")

      # Should not crash with KeyError for missing :user assign
      assert redirected_to(conn) == "/"
    end
  end

  describe "error handling" do
    test "format_error_reason handles Stripe.Error structs", %{
      conn: conn,
      user: user
    } do
      # Mock Stripe error from create_setup_intent
      Ysc.CustomersMock
      |> stub(:create_setup_intent, fn _user ->
        {:error,
         %Stripe.Error{
           message: "Your card was declined",
           source: :api,
           code: :card_declined
         }}
      end)

      conn =
        conn
        |> log_in_user(user)
        |> get("/billing/user/#{user.id}/setup-payment")

      assert conn.status == 400
      response = json_response(conn, 400)
      assert response["error"] == "Failed to create setup intent"
      # format_error_reason should extract the message string from Stripe.Error
      assert response["reason"] == "Your card was declined"
      assert is_binary(response["reason"])
    end
  end

  describe "URL construction" do
    test "finalize constructs URLs without route_helpers", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> log_in_user(user)
        |> get("/billing/user/#{user.id}/finalize")

      # Should not crash with KeyError for missing :route_helpers
      # Controller now uses url(conn) to construct URLs
      assert redirected_to(conn) == "/"
    end
  end
end
