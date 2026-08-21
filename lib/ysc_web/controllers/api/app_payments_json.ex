defmodule YscWeb.Api.AppPaymentsJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's payments endpoints.
  """

  def connection_token(%{connection_token: connection_token}) do
    %{secret: connection_token.secret}
  end
end
