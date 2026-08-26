defmodule YscWeb.Plugs.TimeZone do
  @moduledoc """
  Assigns `:timezone` from the browser (LiveSocket connect params).

  Invalid or missing values fall back to Pacific time so templates can always
  read `@timezone`.
  """

  def on_mount(:assign_timezone, _params, _session, socket) do
    {:cont,
     Phoenix.Component.assign(
       socket,
       :timezone,
       YscWeb.TimeZone.from_connect_params(socket)
     )}
  end
end
