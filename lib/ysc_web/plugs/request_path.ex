defmodule YscWeb.Plugs.RequestPath do
  @moduledoc """
  LiveView mount hook for setting request_path assign.

  Sets the request_path assign from the URI in handle_params so the app layout
  can check if the current route should be fullscreen.
  """
  def on_mount(:set_request_path, _params, _session, socket) do
    {:cont,
     Phoenix.LiveView.attach_hook(
       socket,
       :set_request_path,
       :handle_params,
       &set_request_path/3
     )}
  end

  defp set_request_path(_params, uri, socket) do
    parsed_uri = URI.parse(uri)
    path = parsed_uri.path || ""
    {:cont, Phoenix.Component.assign(socket, :request_path, path)}
  end
end
