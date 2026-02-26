defmodule YscWeb.LiveToastMount do
  @moduledoc """
  Assigns :toasts_sync for LiveToast 0.8 so the layout can pass it to toast_group.
  Add `{YscWeb.LiveToastMount, :mount_toasts_sync}` to each live_session's on_mount.
  """
  def on_mount(:mount_toasts_sync, _params, _session, socket) do
    {:cont, Phoenix.LiveView.Utils.assign(socket, :toasts_sync, [])}
  end
end
