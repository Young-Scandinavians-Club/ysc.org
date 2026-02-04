defmodule YscWeb.UserConfirmationLive do
  use YscWeb, :live_view

  alias Ysc.Accounts

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <div class="max-w-sm mx-auto py-10">
      <.link
        navigate={~p"/"}
        class="flex items-center text-center justify-center py-10 hover:opacity-80 transition duration-200 ease-in-out"
      >
        <.ysc_logo class="h-28" />
      </.link>
      <.header class="text-center">
        Confirm Email
      </.header>

      <.simple_form for={@form} id="confirmation_form" phx-submit="confirm_account">
        <.input field={@form[:token]} type="hidden" />
        <:actions>
          <.button phx-disable-with="Confirming..." class="w-full">
            Confirm my account
          </.button>
        </:actions>
      </.simple_form>

      <p class="text-center mt-4">
        <.link navigate={~p"/users/log-in"}>Sign in</.link>
      </p>
    </div>
    """
  end

  @spec mount(map(), any(), any()) ::
          {:ok, any(), [{:temporary_assigns, [...]}, ...]}
  def mount(%{"token" => token}, _session, socket) do
    form = to_form(%{"token" => token}, as: "user")

    {:ok, assign(socket, form: form) |> assign(:page_title, "Confirm Email"),
     temporary_assigns: [form: nil]}
  end

  # Do not sign in the user after confirmation to avoid a
  # leaked token giving the user access to the account.
  @spec handle_event(<<_::120>>, map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("confirm_account", %{"user" => %{"token" => token}}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User confirmed successfully.")
         |> redirect(to: ~p"/")}

      :error ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        case socket.assigns do
          %{current_user: %{confirmed_at: confirmed_at}}
          when not is_nil(confirmed_at) ->
            {:noreply, redirect(socket, to: ~p"/")}

          %{} ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               "User confirmation link is invalid or it has expired."
             )
             |> redirect(to: ~p"/")}
        end
    end
  end
end
