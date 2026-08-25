defmodule YscWeb.Api.AppPaymentsJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's payments endpoints.
  """

  def connection_token(%{
        connection_token: connection_token,
        location_id: location_id
      }) do
    %{secret: connection_token.secret, location_id: location_id}
  end
end
