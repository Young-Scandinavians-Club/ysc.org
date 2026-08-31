defmodule YscWeb.Api.FallbackController do
  @moduledoc """
  Fallback controller for mobile API error handling.
  """
  use YscWeb, :controller

  def call(conn, {:error, :missing_property}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "property is required. Use 'tahoe' or 'clear_lake'"})
  end

  def call(conn, {:error, :invalid_property}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid property. Use 'tahoe' or 'clear_lake'"})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not found"})
  end

  def call(conn, {:error, {:invalid_date, key}}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "invalid date format for '#{key}'. Use ISO 8601 (YYYY-MM-DD)"
    })
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors = YscWeb.FormHelpers.changeset_errors(changeset)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation failed", errors: errors})
  end

  def call(conn, {:error, %Stripe.Error{} = error}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: Ysc.PaymentUserMessages.format_stripe_error(error)})
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: reason})
  end

  # Errors surfaced by the admin/volunteer mobile app's endpoints
  # (AppTicketsController, AppMembershipsController, AppPaymentsController).
  @app_error_messages %{
    member_not_found: "member not found",
    user_not_found: "member not found",
    ticket_tier_not_found: "ticket tier not found",
    event_not_found: "event not found",
    membership_required: "member does not have an active membership",
    invalid_plan: "invalid membership plan",
    invalid_offline_payment_method:
      "payment_method must be one of: cash, check, other",
    could_not_create_stripe_customer:
      "could not set up billing for this member — try again",
    empty_selection: "select at least one ticket",
    invalid_ticket_tier: "one or more selected ticket tiers are invalid",
    invalid_quantity: "one or more selected ticket quantities are invalid",
    donation_tier_not_grantable:
      "donation ticket tiers cannot be sold via the in-person app",
    incomplete_member_profile:
      "this ticket tier needs the member's name and email on file first",
    tier_not_on_sale: "one or more selected ticket tiers are not on sale",
    terminal_not_configured:
      "Stripe Terminal is not configured for this environment",
    user_already_has_active_subscription:
      "member already has an active membership",
    payment_method_not_eligible:
      "payment method must be collected for this member via Terminal just before subscribe",
    sub_accounts_cannot_create_subscriptions:
      "sub-accounts cannot sign up for their own membership",
    invalid_ticket_selection:
      "one or more selected ticket quantities are invalid",
    donation_tier_not_supported_in_app:
      "donation ticket tiers cannot be charged via the in-person app; collect donations on the website",
    tier_validation_failed:
      "one or more selected ticket tiers are sold out or unavailable",
    insufficient_capacity:
      "not enough tickets remaining for the selected tiers",
    event_capacity_exceeded: "this event is at capacity",
    event_not_available: "this event is not available for ticket sales",
    event_cancelled: "this event has been cancelled",
    event_in_past: "this event has already happened",
    reservation_lapsed: "the ticket reservation expired — please try again",
    checkout_payment_in_progress:
      "a payment is already in progress for this member and event"
  }

  @app_not_found_errors [
    :member_not_found,
    :user_not_found,
    :ticket_tier_not_found,
    :event_not_found
  ]

  for {reason, message} <- Map.take(@app_error_messages, @app_not_found_errors) do
    def call(conn, {:error, unquote(reason)}) do
      conn
      |> put_status(:not_found)
      |> json(%{error: unquote(message)})
    end
  end

  for {reason, message} <- Map.drop(@app_error_messages, @app_not_found_errors) do
    def call(conn, {:error, unquote(reason)}) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: unquote(message)})
    end
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "an unexpected error occurred"})
  end
end
