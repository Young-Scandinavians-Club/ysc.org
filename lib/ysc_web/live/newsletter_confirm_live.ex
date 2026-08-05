defmodule YscWeb.NewsletterConfirmLive do
  @moduledoc """
  Public landing page for confirming a double opt-in newsletter subscription
  via a link in the confirmation email.

  Route: /newsletter/confirm/:token
  """
  use YscWeb, :live_view

  alias Ysc.Newsletter

  @impl true
  def mount(%{"token" => token} = _params, _session, socket) do
    result = safe_confirm_subscription(token)

    socket =
      socket
      |> assign(:page_title, "Confirm Newsletter Subscription")
      |> assign(
        :meta_description,
        "Confirm your subscription to the Young Scandinavians Club newsletter."
      )
      |> assign(:subscriber, confirmed_subscriber(result))
      |> assign(:error, result == {:error, :not_found})

    {:ok, socket}
  end

  defp safe_confirm_subscription(token) when is_binary(token) do
    if String.trim(token) == "" do
      {:error, :not_found}
    else
      Newsletter.confirm_subscription(token)
    end
  end

  defp safe_confirm_subscription(_token), do: {:error, :not_found}

  defp confirmed_subscriber({:ok, subscriber}), do: subscriber
  defp confirmed_subscriber(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-16 lg:py-24 max-w-xl mx-auto px-4" id="newsletter-confirm-page">
      <div class="text-center">
        <h1 :if={@subscriber} class="text-2xl font-bold text-zinc-900">
          You're subscribed!
        </h1>
        <h1 :if={!@subscriber} class="text-2xl font-bold text-zinc-900">
          Invalid or expired link
        </h1>

        <p :if={@subscriber} class="mt-4 text-zinc-600">
          <strong>{@subscriber.email}</strong>
          is now confirmed for the YSC newsletter. Look out for our next edition in your inbox.
        </p>

        <p :if={!@subscriber} class="mt-4 text-zinc-600">
          This link does not work. It may be outdated or mistyped. If you'd like to subscribe, you can sign up again from our home page.
        </p>

        <.link navigate={~p"/"} class="mt-8 inline-block">
          <.button>Return to home</.button>
        </.link>
      </div>
    </div>
    """
  end
end
