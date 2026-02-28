defmodule YscWeb.Flash do
  @moduledoc """
  Centralized toast/flash facade. All callers use these functions so styling,
  placement, and behavior can be changed in one place.

  For `:info`, `:error`, and `:warning` a default title and icon are applied
  (Success / Error / Warning). Pass `title: "Context"` to show a clearer label.
  """

  @doc """
  Drop-in replacement for put_flash. Use in pipelines with socket or conn.

  ## Examples

      conn
      |> YscWeb.Flash.put_toast(:info, "Saved successfully.")

      {:noreply, YscWeb.Flash.put_toast(socket, :error, "Something went wrong.")}
  """
  def put_toast(conn_or_socket, kind, msg, opts \\ [])

  def put_toast(%Plug.Conn{} = conn, kind, msg, opts),
    do: LiveToast.put_toast(conn, kind, msg, default_icon_opts(kind, opts))

  def put_toast(socket, kind, msg, opts),
    do: LiveToast.put_toast(socket, kind, msg, default_icon_opts(kind, opts))

  @doc """
  Send a toast without pipeline (e.g. in handle_event). Use when you need to
  show a toast and return the socket in the same callback.

  ## Examples

      def handle_event("submit", _params, socket) do
        LiveToast.send_toast(:info, "Upload successful.")
        {:noreply, socket}
      end
  """
  def send_toast(kind, msg, opts \\ []) do
    LiveToast.send_toast(kind, msg, default_icon_opts(kind, opts))
  end

  defp default_icon_opts(kind, opts) do
    {icon, default_title} =
      case kind do
        :info ->
          {&YscWeb.CoreComponents.flash_toast_icon_success/1, "Success"}

        :error ->
          {&YscWeb.CoreComponents.flash_toast_icon_error/1, "Error"}

        :warning ->
          {&YscWeb.CoreComponents.flash_toast_icon_warning/1, "Warning"}

        _ ->
          {nil, nil}
      end

    opts
    |> maybe_put(:icon, icon, Keyword.has_key?(opts, :icon))
    # LiveToast only renders the icon inside the title block; without a title the icon is never shown.
    |> maybe_put(
      :title,
      default_title,
      icon != nil && !Keyword.has_key?(opts, :title)
    )
  end

  defp maybe_put(opts, _key, _value, false), do: opts
  defp maybe_put(opts, key, value, true), do: Keyword.put(opts, key, value)

  @doc "Convenience: success toast (kind :info)."
  def success(conn_or_socket, msg, opts \\ []) do
    put_toast(conn_or_socket, :info, msg, opts)
  end

  @doc "Convenience: error toast (kind :error)."
  def error(conn_or_socket, msg, opts \\ []) do
    put_toast(conn_or_socket, :error, msg, opts)
  end

  @doc """
  Success toast with a title. Use for high-value confirmations (e.g. payment, booking).

  A default success icon is shown unless you pass a custom `:icon` (a function component).
  """
  def success_with_title(conn_or_socket, title, msg, opts \\ []) do
    put_toast(conn_or_socket, :info, msg, Keyword.put_new(opts, :title, title))
  end

  @doc "Error toast with a title. Use for validation or critical errors."
  def error_with_title(conn_or_socket, title, msg, opts \\ []) do
    put_toast(conn_or_socket, :error, msg, Keyword.put_new(opts, :title, title))
  end
end
