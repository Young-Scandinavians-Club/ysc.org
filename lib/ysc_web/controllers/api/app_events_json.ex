defmodule YscWeb.Api.AppEventsJSON do
  @moduledoc """
  JSON rendering for the admin/volunteer mobile app's events endpoint.

  Same response shape as the kiosk API's events list — reuses `EventsJSON`
  directly rather than duplicating it.
  """

  defdelegate index(assigns), to: YscWeb.Api.EventsJSON
end
