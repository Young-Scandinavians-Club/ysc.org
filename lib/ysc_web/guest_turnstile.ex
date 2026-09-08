defmodule YscWeb.GuestTurnstile do
  @moduledoc """
  Shared Cloudflare Turnstile verification for public forms.

  Contact, volunteer, and conduct-report LiveViews skip the widget for
  signed-in members. Registration always verifies. Failed checks toast the
  same copy and refresh the widget.

  Resolves the Turnstile module from `:phoenix_turnstile, :turnstile_module`
  so tests can stub `TurnstileMock`.

  ## Examples

      def handle_event("save", params, socket) do
        case GuestTurnstile.verify(socket, params, title: "Contact") do
          :ok -> save_form(socket, params)
          {:error, socket} -> {:noreply, assign_form(socket, changeset)}
        end
      end

      GuestTurnstile.verify(socket, params,
        title: "Registration",
        required: true
      )
  """

  @error_message "We couldn't verify you're a real person. Please try submitting again. If this keeps happening, refresh the page or try a different browser."

  @doc """
  Human-readable error shown after a failed Turnstile check.
  """
  def error_message, do: @error_message

  @doc """
  Returns the configured Turnstile module (`Turnstile` in prod, `TurnstileMock` in tests).
  """
  def module,
    do: Application.get_env(:phoenix_turnstile, :turnstile_module, Turnstile)

  @doc """
  Verifies Turnstile for a form submit.

  Returns `:ok` or `{:error, socket}` with an error toast and a refreshed widget.

  ## Options

    * `:title` — required toast title on failure
    * `:required` — when `true`, always verify (registration). When `false`
      (default), signed-in members skip the check.
  """
  def verify(socket, params, opts) when is_map(params) and is_list(opts) do
    title = Keyword.fetch!(opts, :title)
    required? = Keyword.get(opts, :required, false)

    if required? or not signed_in?(socket) do
      case module().verify(params, socket.assigns.remote_ip) do
        {:ok, _} -> :ok
        {:error, _} -> {:error, reject(socket, title)}
      end
    else
      :ok
    end
  end

  defp reject(socket, title) do
    socket
    |> YscWeb.Flash.put_toast(:error, @error_message, title: title)
    |> module().refresh()
  end

  defp signed_in?(socket), do: socket.assigns[:logged_in?] == true
end
