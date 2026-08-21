defmodule YscWeb.Api.AppPaymentsController do
  @moduledoc """
  Stripe Terminal support for the admin/volunteer mobile app's tap-to-pay
  checkout (see `Ysc.StripeClient.create_terminal_connection_token/1`).
  """
  use YscWeb, :controller

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
    with location_id when is_binary(location_id) and location_id != "" <-
           Application.get_env(:ysc, :stripe_terminal_location_id),
         {:ok, connection_token} <-
           stripe_client().create_terminal_connection_token(%{location: location_id}) do
      render(conn, :connection_token, connection_token: connection_token)
    else
      _ -> {:error, :terminal_not_configured}
    end
  end
end
