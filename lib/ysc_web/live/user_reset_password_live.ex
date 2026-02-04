defmodule YscWeb.UserResetPasswordLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.AuthService
  alias Ysc.Accounts.UserNotifier

  def render(assigns) do
    ~H"""
    <div class="max-w-sm mx-auto py-10">
      <.link
        navigate={~p"/"}
        class="flex items-center text-center justify-center py-10 hover:opacity-80 transition duration-200 ease-in-out"
      >
        <.ysc_logo class="h-28" />
      </.link>
      <.header class="text-center">
        Reset Your Password
      </.header>

      <.simple_form
        for={@form}
        id="reset_password_form"
        phx-submit="reset_password"
        phx-change="validate"
      >
        <.input
          field={@form[:password]}
          type="password-toggle"
          label="New password"
          required
        />
        <.input
          field={@form[:password_confirmation]}
          type="password-toggle"
          label="Confirm new password"
          required
        />
        <:actions>
          <.button phx-disable-with="Resetting..." class="w-full">
            Reset Password
          </.button>
        </:actions>
      </.simple_form>

      <p class="text-center text-sm mt-4">
        <.link href={~p"/users/log-in"}>Sign in</.link>
      </p>
    </div>
    """
  end

  def mount(params, _session, socket) do
    remote_ip =
      get_connect_info(socket, :peer_data) |> Map.get(:address, {0, 0, 0, 0})

    socket =
      assign(socket, :remote_ip, remote_ip) |> assign_user_and_token(params)

    form_source =
      case socket.assigns do
        %{user: user} ->
          Accounts.change_user_password(user)

        _ ->
          %{}
      end

    {:ok,
     assign_form(socket, form_source) |> assign(:page_title, "Reset Password"),
     temporary_assigns: [form: nil]}
  end

  # Do not sign in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    ip = socket.assigns[:remote_ip] || {0, 0, 0, 0}

    case Ysc.AuthRateLimit.check_ip(ip) do
      {:error, :rate_limited, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Too many attempts. Please try again later.")
         |> redirect(to: ~p"/users/log-in")}

      :ok ->
        do_reset_password(socket, user_params)
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp do_reset_password(socket, user_params) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, user} ->
        # Log successful password reset
        AuthService.log_password_reset_success(socket.assigns.user, socket)

        # Send password changed notification
        UserNotifier.deliver_password_changed_notification(user)

        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
