defmodule YscWeb.Flash do
  @moduledoc """
  Centralized toast/flash facade. All callers use these functions so styling,
  placement, and behavior can be changed in one place.
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
    do: LiveToast.put_toast(conn, kind, msg, opts)

  def put_toast(socket, kind, msg, opts),
    do: LiveToast.put_toast(socket, kind, msg, opts)

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
    LiveToast.send_toast(kind, msg, opts)
  end

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

  For icons, pass a function component from your LiveView, e.g.:
  `icon: fn assigns -> ~H"<.icon name=\"hero-check-circle\" class=\"w-5 h-5\" />" end`
  """
  def success_with_title(conn_or_socket, title, msg, opts \\ []) do
    put_toast(conn_or_socket, :info, msg, Keyword.put_new(opts, :title, title))
  end

  @doc "Error toast with a title. Use for validation or critical errors."
  def error_with_title(conn_or_socket, title, msg, opts \\ []) do
    put_toast(conn_or_socket, :error, msg, Keyword.put_new(opts, :title, title))
  end
end
