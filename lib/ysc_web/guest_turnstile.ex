defmodule YscWeb.GuestTurnstile do
  @moduledoc """
  Shared Cloudflare Turnstile verification for public forms.

  Contact, volunteer, and conduct-report LiveViews skip the widget for
  signed-in members. Registration always verifies. Contact and volunteer also
  reject a missing token (`require_token: true`). Failed checks toast the
  same copy and refresh the widget. Guest newsletter signups use
  `verify_token/2` and `refresh/1` directly to show their own inline error.

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

      GuestTurnstile.verify(socket, params,
        title: "Contact",
        require_token: true
      )
  """

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
    * `:required` — when `true`, always verify (registration). When `false`
      (default), signed-in members skip the check.
    * `:require_token` — when `true`, a missing or blank token fails the check
      without calling Cloudflare (see `verify_token/2`). Default `false`.
  """
  def verify(socket, params, opts) when is_map(params) and is_list(opts) do
    title = Keyword.fetch!(opts, :title)
    required? = Keyword.get(opts, :required, false)
    require_token? = Keyword.get(opts, :require_token, false)

    if required? or not signed_in?(socket) do
      case check(params, socket.assigns.remote_ip, require_token?) do
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

  Returns `:ok` or `{:error, reason}`.
  """
  def verify_token(params, remote_ip) when is_map(params) do
    case Map.get(params, @token_param) do
      token when is_binary(token) and token != "" ->
        case module().verify(params, remote_ip) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :missing_token}
    end
  end

  @doc """
  Resets the Turnstile widget on the client after a failed check.
  """
  def refresh(socket), do: module().refresh(socket)

  defp check(params, remote_ip, true), do: verify_token(params, remote_ip)

  defp check(params, remote_ip, false) do
    case module().verify(params, remote_ip) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp reject(socket, title) do
    socket
    |> YscWeb.Flash.put_toast(:error, @error_message, title: title)
    |> refresh()
  end

  defp signed_in?(socket), do: socket.assigns[:logged_in?] == true
end
