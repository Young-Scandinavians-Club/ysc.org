defmodule YscWeb.GuestTurnstile do
  @moduledoc """
  Shared Cloudflare Turnstile verification for public forms.

  Contact, volunteer, and conduct-report LiveViews skip the widget for
  signed-in members. A missing or blank token fails without calling
  Cloudflare, so clients can't bypass the check by omitting the field. Failed
  checks toast the same copy and refresh the widget. Guest newsletter signups
  use `verify_token/3` and `refresh/1` directly to show their own inline
  error.

  The membership application (`UserRegistrationLive`) doesn't use Turnstile
  for now. To turn it back on: assign `:remote_ip` in its `mount/3` (which
  `verify/3` reads), render the widget in its form, call `verify/3` with
  `required: true` in its save handler, and restore its tests for a failed
  check.

  Resolves the Turnstile module from `:phoenix_turnstile, :turnstile_module`
  so tests can stub `TurnstileMock`.

  Every rejection logs a warning with the form and the reason
  (`missing_token` or Cloudflare's error codes).

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

  require Ysc.Logging

  @token_param "cf-turnstile-response"

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
    * `:required` — when `true`, verify signed-in sockets too (meant for
      registration). When `false` (default), signed-in members skip the check.
  """
  def verify(socket, params, opts) when is_map(params) and is_list(opts) do
    title = Keyword.fetch!(opts, :title)
    required? = Keyword.get(opts, :required, false)

    if required? or not signed_in?(socket) do
      case verify_token(params, socket.assigns.remote_ip, form: title) do
        :ok -> :ok
        {:error, _} -> {:error, reject(socket, title)}
      end
    else
      :ok
    end
  end

  @doc """
  Verifies the `"cf-turnstile-response"` token in `params`.

  A missing or blank token is rejected without calling Cloudflare, so clients
  can't bypass the check by omitting the field.

  Returns `:ok` or `{:error, reason}`, and logs a warning on rejection.

  ## Options

    * `:form` — label for the log line (e.g. `"Contact"`)
  """
  def verify_token(params, remote_ip, opts \\ [])
      when is_map(params) and is_list(opts) do
    case Map.get(params, @token_param) do
      token when is_binary(token) and token != "" ->
        case module().verify(params, remote_ip) do
          {:ok, _} -> :ok
          {:error, reason} -> log_rejection(reason, opts)
        end

      _ ->
        log_rejection(:missing_token, opts)
    end
  end

  @doc """
  Short, log-friendly description of a `verify_token/3` failure reason.
  """
  def rejection_reason(:missing_token), do: "missing_token"

  def rejection_reason(%{"error-codes" => [_ | _] = codes}),
    do: Enum.join(codes, ",")

  def rejection_reason(reason), do: inspect(reason, limit: 20)

  @doc """
  Resets the Turnstile widget on the client after a failed check.
  """
  def refresh(socket), do: module().refresh(socket)

  defp log_rejection(reason, opts) do
    Ysc.Logging.warning("Turnstile check failed",
      form: Keyword.get(opts, :form),
      turnstile_reason: rejection_reason(reason)
    )

    {:error, reason}
  end

  defp reject(socket, title) do
    socket
    |> YscWeb.Flash.put_toast(:error, @error_message, title: title)
    |> refresh()
  end

  defp signed_in?(socket), do: socket.assigns[:logged_in?] == true
end
