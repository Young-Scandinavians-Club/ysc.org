defmodule YscWeb.Api.AppPaymentsController do
  @moduledoc """
  Stripe Terminal support for the admin/volunteer mobile app's tap-to-pay
  checkout (see `Ysc.StripeClient.create_terminal_connection_token/1`).
  """
  use YscWeb, :controller

  require Ysc.Logging

  action_fallback YscWeb.Api.FallbackController

  defp stripe_client do
    Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)
  end

  @doc """
  Issues a fresh Stripe Terminal connection token so the app's Stripe
  Terminal SDK can initialize and discover a (local mobile or physical)
  reader. Connection tokens are short-lived and requested per session.
  """
  def connection_token(conn, _params) do
    location_id = Application.get_env(:ysc, :stripe_terminal_location_id)

    cond do
      not is_binary(location_id) or location_id == "" ->
        {:error, :terminal_not_configured}

      true ->
        case stripe_client().create_terminal_connection_token(%{
               location: location_id
             }) do
          {:ok, connection_token} ->
            render(conn, :connection_token,
              connection_token: connection_token,
              location_id: location_id
            )

          {:error, %Stripe.Error{} = error} = result ->
            Ysc.Logging.error(
              "Failed to create Stripe Terminal connection token",
              error: error
            )

            result

          {:error, reason} = result ->
            Ysc.Logging.error(
              "Failed to create Stripe Terminal connection token",
              extra: %{reason: inspect(reason)}
            )

            result
        end
    end
  end
end
