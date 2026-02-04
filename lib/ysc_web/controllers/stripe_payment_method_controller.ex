defmodule Ysc.Controllers.StripePaymentMethodController do
  @moduledoc false

  use Phoenix.Controller,
    formats: [:html, :json]

  # Removed Bling.Plugs.AssignCustomer - will implement custom logic

  # Allow dependency injection for testing
  @payment_method_module Application.compile_env(
                           :ysc,
                           :stripe_payment_method_module,
                           Stripe.PaymentMethod
                         )
  @setup_intent_module Application.compile_env(
                         :ysc,
                         :stripe_setup_intent_module,
                         Stripe.SetupIntent
                       )
  @payment_intent_module Application.compile_env(
                           :ysc,
                           :stripe_payment_intent_module,
                           Stripe.PaymentIntent
                         )
  @customer_module Application.compile_env(
                     :ysc,
                     :stripe_customer_module,
                     Stripe.Customer
                   )
  @customers_module Application.compile_env(
                      :ysc,
                      :customers_module,
                      Ysc.Customers
                    )
  @payments_module Application.compile_env(:ysc, :payments_module, Ysc.Payments)

  def finalize(conn, _params) do
    props = get_props(conn)

    if props.payment_intent || props.setup_intent do
      conn
      |> assign(:props, props)
      |> render(:finalize)
    else
      redirect(conn, to: "/")
    end
  end

  def setup_payment(conn, _params) do
    # Get user from user_id in params
    user_id = conn.path_params["user_id"]

    try do
      user = Ysc.Accounts.get_user!(user_id)

      case @customers_module.create_setup_intent(user) do
        {:ok, intent} ->
          conn |> json(%{client_secret: intent.client_secret})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            error: "Failed to create setup intent",
            reason: format_error_reason(reason)
          })
      end
    rescue
      Ecto.Query.CastError ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid user ID format"})

      Ecto.NoResultsError ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})
    end
  end

  def store_payment_method(conn, params) do
    user = conn.assigns.current_user
    payment_method_id = params["payment_method_id"]

    # Validate payment_method_id is present
    if is_nil(payment_method_id) || payment_method_id == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Payment method ID is required"})
    else
      do_store_payment_method(conn, user, payment_method_id)
    end
  end

  defp do_store_payment_method(conn, user, payment_method_id) do
    with {:ok, stripe_payment_method} <-
           retrieve_stripe_payment_method(payment_method_id),
         {:ok, _} <-
           @payments_module.upsert_and_set_default_payment_method_from_stripe(
             user,
             stripe_payment_method
           ),
         {:ok, _stripe_customer} <-
           @customer_module.update(
             user.stripe_id,
             %{invoice_settings: %{default_payment_method: payment_method_id}},
             []
           ) do
      # Reload user to get updated payment method info
      updated_user = Ysc.Accounts.get_user!(user.id)

      conn
      |> assign(:current_user, updated_user)
      |> json(%{
        success: true,
        message: "Payment method stored and set as default successfully"
      })
    else
      {:error, :stripe_error} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to retrieve payment method from Stripe"})

      {:error, %Stripe.Error{} = stripe_error} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Failed to update Stripe customer",
          reason: stripe_error.message
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Failed to store payment method",
          details: changeset.errors
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{
          error: "Failed to store payment method",
          reason: format_error_reason(reason)
        })
    end
  end

  # Private helper functions

  # Format error reasons to be JSON-encodable
  defp format_error_reason(%Stripe.Error{} = error), do: error.message
  defp format_error_reason(reason) when is_binary(reason), do: reason

  defp format_error_reason(reason) when is_atom(reason),
    do: Atom.to_string(reason)

  defp format_error_reason(reason), do: inspect(reason)

  defp retrieve_stripe_payment_method(payment_method_id) do
    case @payment_method_module.retrieve(payment_method_id) do
      {:ok, payment_method} -> {:ok, payment_method}
      {:error, _} -> {:error, :stripe_error}
    end
  end

  defp get_props(conn) do
    # Construct URLs using Phoenix.Controller.current_url/1
    base_url =
      Phoenix.Controller.current_url(conn)
      |> String.replace(~r{/finalize.*$}, "")

    finalize_url = "#{base_url}/finalize"

    %{
      finalize_url: finalize_url,
      base_url: base_url,
      return_to: "/",
      payment_intent: maybe_get_payment_intent(conn),
      setup_intent: maybe_get_setup_intent(conn)
    }
  end

  defp maybe_get_setup_intent(conn) do
    id = Map.get(conn.params, "setup_intent")

    with id when not is_nil(id) <- id,
         {:ok, intent} <- @setup_intent_module.retrieve(id, %{}),
         true <- intent.customer == conn.assigns.current_user.stripe_id do
      Map.take(intent, [:id, :client_secret, :status, :payment_method])
    else
      _ -> nil
    end
  end

  defp maybe_get_payment_intent(conn) do
    id = Map.get(conn.params, "payment_intent")

    with id when not is_nil(id) <- id,
         {:ok, intent} <- @payment_intent_module.retrieve(id, %{}),
         true <- intent.customer == conn.assigns.current_user.stripe_id do
      Map.take(intent, [:id, :client_secret, :amount, :currency, :status])
    else
      _ -> nil
    end
  end
end
