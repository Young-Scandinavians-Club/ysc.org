defmodule YscWeb.LiveToastMount do
  @moduledoc """
  Assigns :toasts_sync for LiveToast so the layout can pass it to toast_group.
  Required by LiveToast: the layout must pass flash, connected, and toasts_sync.
  """
  def on_mount(:mount_toasts_sync, _params, _session, socket) do
    socket = Phoenix.LiveView.Utils.assign(socket, :toasts_sync, [])
    {:cont, socket}
  end
end
