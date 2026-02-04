defmodule YscWeb.PaymentSuccessLive do
  @moduledoc """
  LiveView for handling Stripe payment redirects from external payment methods
  (like Amazon Pay, CashApp, etc.) and redirecting to the appropriate page.

  Handles both successful and failed payments:
  - Successful payments: Redirects to booking receipt or order confirmation page with confetti
  - Failed payments: Redirects to booking checkout or event page with error message
  """
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Tickets
  alias Ysc.Repo
  import Ecto.Query
  require Logger

  # Retry configuration
  @max_retries 5
  @retry_delay_ms 500
  @total_timeout_ms 10_000

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(:error, "You must be signed in to view this page.")
       |> redirect(to: ~p"/")}
    else
      redirect_status = Map.get(params, "redirect_status")
      payment_intent_id = extract_payment_intent_id(params)

      cond do
        redirect_status == "succeeded" ->
          # Payment succeeded - redirect to success page
          if payment_intent_id do
            case redirect_to_success_page_with_retry(payment_intent_id, user) do
              {:ok, redirect_path} ->
                {:ok, redirect(socket, to: redirect_path)}

              {:error, reason} ->
                Logger.error(
                  "Failed to redirect from payment success after retries",
                  payment_intent_id: payment_intent_id,
                  user_id: user.id,
                  error: reason
                )

                {:ok,
                 socket
                 |> put_flash(
                   :error,
                   "Payment was successful, but we couldn't find your booking or order. Please contact support."
                 )
                 |> redirect(to: ~p"/")}
            end
          else
            {:ok,
             socket
             |> put_flash(:error, "Invalid payment information.")
             |> redirect(to: ~p"/")}
          end

        redirect_status in ["failed", "canceled"] ->
          # Payment failed or was canceled - redirect to appropriate page with error
          failure_message = get_failure_message(redirect_status)

          if payment_intent_id do
            case redirect_to_failure_page(
                   payment_intent_id,
                   user,
                   redirect_status
                 ) do
              {:ok, redirect_path} ->
                {:ok,
                 socket
                 |> put_flash(:error, failure_message)
                 |> redirect(to: redirect_path)}

              {:error, reason} ->
                Logger.error("Failed to redirect from payment failure",
                  payment_intent_id: payment_intent_id,
                  user_id: user.id,
                  redirect_status: redirect_status,
                  error: reason
                )

                {:ok,
                 socket
                 |> put_flash(:error, failure_message)
                 |> redirect(to: ~p"/")}
            end
          else
            {:ok,
             socket
             |> put_flash(:error, failure_message)
             |> redirect(to: ~p"/")}
          end

        true ->
          # Unknown or missing redirect status
          {:ok,
           socket
           |> put_flash(
             :error,
             "Payment status is unclear. Please check your booking or order status."
           )
           |> redirect(to: ~p"/")}
      end
    end
  end

  @impl true
  def render(assigns) do
    # This should never render as we always redirect in mount
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4">
      <div class="text-center">
        <p class="text-zinc-600">Processing your payment...</p>
      </div>
    </div>
    """
  end

  ## Private Functions

  defp extract_payment_intent_id(params) do
    # Payment intent can come in different formats:
    # 1. payment_intent=pi_xxx
    # 2. payment_intent_client_secret=pi_xxx_secret_yyy
    cond do
      payment_intent = Map.get(params, "payment_intent") ->
        payment_intent

      client_secret = Map.get(params, "payment_intent_client_secret") ->
        # Extract payment intent ID from client secret (format: pi_xxx_secret_yyy)
        if String.contains?(client_secret, "_secret_") do
          client_secret
          |> String.split("_secret_")
          |> List.first()
        else
          client_secret
        end

      true ->
        nil
    end
  end

  defp redirect_to_success_page_with_retry(payment_intent_id, user) do
    start_time = System.monotonic_time(:millisecond)

    retry_with_timeout(
      fn -> redirect_to_success_page(payment_intent_id, user) end,
      start_time,
      0
    )
  end

  defp retry_with_timeout(fun, start_time, attempt) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    cond do
      elapsed >= @total_timeout_ms ->
        Logger.warning("Retry timeout exceeded",
          elapsed_ms: elapsed,
          attempt: attempt
        )

        {:error, :timeout}

      attempt >= @max_retries ->
        Logger.warning("Max retries exceeded",
          attempt: attempt,
          elapsed_ms: elapsed
        )

        {:error, :max_retries_exceeded}

      true ->
        case fun.() do
          {:ok, _} = success ->
            if attempt > 0 do
              Logger.info("Payment intent found after retry",
                attempt: attempt,
                elapsed_ms: elapsed
              )
            end

            success

          {:error, :payment_intent_not_found} ->
            # Retry if payment intent not found yet
            Process.sleep(@retry_delay_ms)
            retry_with_timeout(fun, start_time, attempt + 1)

          {:error, :no_metadata} ->
            # Retry if metadata not available yet
            Process.sleep(@retry_delay_ms)
            retry_with_timeout(fun, start_time, attempt + 1)

          {:error, _} = error ->
            # Don't retry for other errors (unauthorized, not found, etc.)
            error
        end
    end
  end

  defp redirect_to_success_page(payment_intent_id, user) do
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{}) do
      {:ok, payment_intent} ->
        # Check metadata for booking_id or ticket_order_id
        # Stripe metadata is a map with string keys
        metadata = payment_intent.metadata || %{}

        booking_id = Map.get(metadata, "booking_id")
        ticket_order_id = Map.get(metadata, "ticket_order_id")

        cond do
          not is_nil(booking_id) ->
            # Verify booking belongs to user and redirect to booking receipt
            case verify_and_redirect_booking(booking_id, user) do
              {:ok, redirect_path} -> {:ok, redirect_path}
              error -> error
            end

          not is_nil(ticket_order_id) ->
            # Verify ticket order belongs to user and redirect to order confirmation
            case verify_and_redirect_ticket_order(ticket_order_id, user) do
              {:ok, redirect_path} -> {:ok, redirect_path}
              error -> error
            end

          true ->
            {:error, :no_metadata}
        end

      {:error, reason} ->
        Logger.debug("Failed to retrieve payment intent (will retry)",
          payment_intent_id: payment_intent_id,
          error: reason
        )

        {:error, :payment_intent_not_found}
    end
  end

  defp verify_and_redirect_booking(booking_id, user) do
    # SECURITY: Filter by user_id in the database query to prevent unauthorized access
    booking_query =
      from(b in Bookings.Booking,
        where: b.id == ^booking_id and b.user_id == ^user.id
      )

    case Repo.one(booking_query) do
      nil ->
        {:error, :booking_not_found}

      _booking ->
        {:ok, ~p"/bookings/#{booking_id}/receipt?confetti=true"}
    end
  end

  defp verify_and_redirect_ticket_order(ticket_order_id, user) do
    # SECURITY: Use user-scoped function to prevent unauthorized access
    case Tickets.get_user_ticket_order(user.id, ticket_order_id) do
      nil ->
        {:error, :ticket_order_not_found}

      _ticket_order ->
        {:ok, ~p"/orders/#{ticket_order_id}/confirmation?confetti=true"}
    end
  end

  defp redirect_to_failure_page(payment_intent_id, user, _redirect_status) do
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{}) do
      {:ok, payment_intent} ->
        metadata = payment_intent.metadata || %{}

        booking_id = Map.get(metadata, "booking_id")
        ticket_order_id = Map.get(metadata, "ticket_order_id")

        cond do
          not is_nil(booking_id) ->
            # Redirect to booking checkout page with error
            case verify_booking_access(booking_id, user) do
              {:ok, _booking} ->
                {:ok, ~p"/bookings/checkout/#{booking_id}"}

              error ->
                error
            end

          not is_nil(ticket_order_id) ->
            # Redirect to event page with error
            case verify_ticket_order_access(ticket_order_id, user) do
              {:ok, event_id} ->
                {:ok, ~p"/events/#{event_id}"}

              error ->
                error
            end

          true ->
            {:error, :no_metadata}
        end

      {:error, reason} ->
        Logger.debug("Failed to retrieve payment intent for failure redirect",
          payment_intent_id: payment_intent_id,
          error: reason
        )

        {:error, :payment_intent_not_found}
    end
  end

  defp verify_booking_access(booking_id, user) do
    # SECURITY: Filter by user_id in the database query to prevent unauthorized access
    booking_query =
      from(b in Bookings.Booking,
        where: b.id == ^booking_id and b.user_id == ^user.id
      )

    case Repo.one(booking_query) do
      nil ->
        {:error, :booking_not_found}

      booking ->
        {:ok, booking}
    end
  end

  defp verify_ticket_order_access(ticket_order_id, user) do
    # SECURITY: Use user-scoped function to prevent unauthorized access
    case Tickets.get_user_ticket_order(user.id, ticket_order_id) do
      nil ->
        {:error, :ticket_order_not_found}

      ticket_order ->
        {:ok, ticket_order.event_id}
    end
  end

  defp get_failure_message(redirect_status) do
    case redirect_status do
      "failed" ->
        "Payment failed. Please try again or contact support if the problem persists."

      "canceled" ->
        "Payment was canceled. You can try again when you're ready."

      _ ->
        "Payment was not successful. Please try again or contact support if the problem persists."
    end
  end
end
