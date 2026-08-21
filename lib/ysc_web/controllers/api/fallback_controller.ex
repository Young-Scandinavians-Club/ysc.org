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
    ticket_tier_not_found: "ticket tier not found",
    membership_required: "member does not have an active membership",
    invalid_plan: "invalid membership plan",
    terminal_not_configured: "Stripe Terminal is not configured for this environment",
    user_already_has_active_subscription: "member already has an active membership",
    sub_accounts_cannot_create_subscriptions:
      "sub-accounts cannot sign up for their own membership"
  }

  for {reason, message} <- @app_error_messages do
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
