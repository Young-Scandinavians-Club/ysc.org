defmodule YscWeb.UserConfirmationInstructionsLive do
  use YscWeb, :live_view

  alias Ysc.Accounts

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Didn't get your verification email?
        <:subtitle>Enter your email and we'll send a new link.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="resend_confirmation_form"
        phx-submit="send_instructions"
      >
        <.input field={@form[:email]} type="email" placeholder="Email" required />
        <:actions>
          <.button phx-disable-with="Sending..." class="w-full">
            Send verification email
          </.button>
        </:actions>
      </.simple_form>

      <p class="text-center mt-4">
        <.link navigate={~p"/users/register"}>Apply for membership</.link>
        | <.link navigate={~p"/users/log-in"}>Sign in</.link>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, form: to_form(%{}, as: "user"))
     |> assign(:page_title, "Resend verification email")
     |> assign(
       :meta_description,
       "Request a new verification email for your Young Scandinavians Club account."
     )}
  end

  def handle_event(
        "send_instructions",
        %{"user" => %{"email" => email}},
        socket
      ) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/users/confirm/#{&1}")
      )
    end

    info =
      "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."

    {:noreply,
     socket
     |> YscWeb.Flash.put_toast(:info, info, title: "Confirmation")
     |> redirect(to: ~p"/")}
  end
end
