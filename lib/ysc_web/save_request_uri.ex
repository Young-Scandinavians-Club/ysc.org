defmodule YscWeb.SaveRequestUri do
  @moduledoc """
  LiveView mount hook for saving request URIs.

  Saves the current request URI to allow redirecting users back after authentication.
  """
  def on_mount(:save_request_uri, _params, _session, socket),
    do:
      {:cont,
       Phoenix.LiveView.attach_hook(
         socket,
         :save_request_path,
         :handle_params,
         &save_request_path/3
       )}

  defp save_request_path(_params, url, socket) do
    parsed_uri = URI.parse(url)
    path = parsed_uri.path || ""
    socket = Phoenix.Component.assign(socket, :current_uri, parsed_uri)
    {:cont, Phoenix.Component.assign(socket, :request_path, path)}
  end
end
