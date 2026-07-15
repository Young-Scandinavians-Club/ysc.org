defmodule YscWeb.LiveToastMount do
  @moduledoc """
  Assigns :toasts_sync for LiveToast so the layout can pass it to toast_group.
  Required by LiveToast: the layout must pass flash, connected, and toasts_sync.

  Also clears one-shot flash after the first render so dismissed (or streamed)
  toasts do not come back on the next LiveView event.
  """
  import Phoenix.LiveView

  def on_mount(:mount_toasts_sync, _params, _session, socket) do
    socket =
      socket
      |> Phoenix.LiveView.Utils.assign(:toasts_sync, [])
      |> Phoenix.LiveView.Utils.assign(:allow_flash_display?, true)
      |> attach_hook(
        :clear_consumed_flash,
        :handle_event,
        &clear_consumed_flash/3
      )
      |> attach_hook(
        :clear_consumed_flash,
        :handle_params,
        &clear_consumed_flash/3
      )
      |> attach_hook(
        :clear_consumed_flash,
        :handle_info,
        &clear_consumed_flash_info/2
      )

    {:cont, socket}
  end

  defp clear_consumed_flash(_event, _params, socket) do
    {:cont, maybe_clear_flash(socket)}
  end

  defp clear_consumed_flash_info(_message, socket) do
    {:cont, maybe_clear_flash(socket)}
  end

  defp maybe_clear_flash(socket) do
    if socket.assigns[:allow_flash_display?] do
      Phoenix.LiveView.Utils.assign(socket, :allow_flash_display?, false)
    else
      clear_one_shot_flash(socket)
    end
  end

  defp clear_one_shot_flash(socket) do
    case socket.assigns[:flash] do
      %{} = flash when map_size(flash) > 0 ->
        Enum.reduce(Map.keys(flash), socket, &clear_flash(&2, &1))

      _ ->
        socket
    end
  end
end
