defmodule YscWeb.UserForgotPasswordLive do
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.AuthService

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm py-10">
      <.link
        navigate={~p"/"}
        class="flex items-center text-center justify-center py-10 hover:opacity-80 transition duration-200 ease-in-out"
      >
        <.ysc_logo class="h-28" />
      </.link>
      <.header class="text-center">
        Forgot your password?
        <:subtitle>We'll send a password reset link to your inbox</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="reset_password_form"
        phx-submit="send_email"
        class="py-8"
      >
        <.input field={@form[:email]} type="email" placeholder="Email" required />
        <:actions>
          <.button phx-disable-with="Sending..." class="w-full">
            Send password reset instructions
          </.button>
        </:actions>
      </.simple_form>

      <.back navigate={~p"/users/log-in"}>Back</.back>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    remote_ip =
      get_connect_info(socket, :peer_data) |> Map.get(:address, {0, 0, 0, 0})

    {:ok,
     socket
     |> assign(:form, to_form(%{}, as: "user"))
     |> assign(:page_title, "Forgot Password")
     |> assign(:remote_ip, remote_ip)}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    ip = socket.assigns[:remote_ip] || {0, 0, 0, 0}

    cond do
      rate_limited_ip?(ip) ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Too many attempts from your connection. Please try again later."
         )
         |> redirect(to: ~p"/users/reset-password")}

      rate_limited_identifier?(email) ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Too many attempts for this email. Please try again later."
         )
         |> redirect(to: ~p"/users/reset-password")}

      true ->
        if user = Accounts.get_user_by_email(email) do
          # Log password reset request
          AuthService.log_password_reset_request(user, socket)

          Accounts.deliver_user_reset_password_instructions(
            user,
            &url(~p"/users/reset-password/#{&1}")
          )
        end

        info =
          "If your email is in our system, you will receive instructions to reset your password shortly."

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> redirect(to: ~p"/")}
    end
  end

  defp rate_limited_ip?(ip) do
    case Ysc.AuthRateLimit.check_ip(ip) do
      :ok -> false
      {:error, :rate_limited, _} -> true
    end
  end

  defp rate_limited_identifier?(email) when is_binary(email) do
    case Ysc.AuthRateLimit.check_identifier(email) do
      :ok -> false
      {:error, :rate_limited, _} -> true
    end
  end

  defp rate_limited_identifier?(_), do: false
end
