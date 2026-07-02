defmodule YscWeb.NewsletterUnsubscribeLive do
  @moduledoc """
  Public page for unsubscribing from the newsletter via a link in an email.

  Route: /newsletter/unsubscribe/:token
  """
  use YscWeb, :live_view

  alias Ysc.Newsletter

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    # Only look up by token if it's a non-empty string (avoids crashes on nil/blank)
    subscriber = safe_get_subscriber_by_token(token)

    # Show success state if already unsubscribed (idempotent: safe to reload link)
    unsubscribed = subscriber != nil && !subscriber.subscribed

    socket =
      socket
      |> assign(:page_title, "Unsubscribe from Newsletter")
      |> assign(
        :meta_description,
        "Unsubscribe from the Young Scandinavians Club newsletter."
      )
      |> assign(:token, token || "")
      |> assign(:subscriber, subscriber)
      |> assign(:unsubscribed, unsubscribed)
      |> assign(:error, nil)

    {:ok, socket}
  end

  defp safe_get_subscriber_by_token(token) when is_binary(token) do
    if String.trim(token) == "" do
      nil
    else
      Newsletter.get_subscriber_by_token(token)
    end
  end

  defp safe_get_subscriber_by_token(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="py-16 lg:py-24 max-w-xl mx-auto px-4"
      id="newsletter-unsubscribe-page"
    >
      <div class="text-center">
        <h1
          :if={@subscriber && !@unsubscribed}
          class="text-2xl font-bold text-zinc-900"
        >
          Unsubscribe from our newsletter
        </h1>
        <h1
          :if={@subscriber && @unsubscribed}
          class="text-2xl font-bold text-zinc-900"
        >
          You have been unsubscribed
        </h1>
        <h1 :if={!@subscriber} class="text-2xl font-bold text-zinc-900">
          Invalid or expired link
        </h1>

        <p :if={@subscriber && !@unsubscribed} class="mt-4 text-zinc-600">
          You are subscribed as <strong><%= @subscriber.email %></strong>. Click below to stop receiving our newsletter.
        </p>

        <p :if={@subscriber && @unsubscribed} class="mt-4 text-zinc-600">
          You will no longer receive our newsletter. You can sign up again anytime from our home page.
        </p>

        <p :if={!@subscriber} class="mt-4 text-zinc-600">
          This link does not work. It may be outdated or mistyped. If you still receive our newsletter, email
          <.link
            href="mailto:info@ysc.org"
            class="text-blue-600 hover:underline font-semibold"
          >
            info@ysc.org
          </.link>
          with the address you want removed and we will unsubscribe you manually.
        </p>

        <.button
          :if={@subscriber && !@unsubscribed}
          phx-click="unsubscribe"
          class="mt-8"
        >
          Unsubscribe
        </.button>

        <.link
          :if={@subscriber && @unsubscribed}
          navigate={~p"/"}
          class="mt-8 inline-block"
        >
          <.button>Return to home</.button>
        </.link>

        <.link :if={!@subscriber} navigate={~p"/"} class="mt-8 inline-block">
          <.button>Return to home</.button>
        </.link>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("unsubscribe", _params, socket) do
    token = socket.assigns.token

    # Guard: only call context if we have a valid token string (never crash)
    result =
      if is_binary(token) && String.trim(token) != "" do
        Newsletter.unsubscribe(token)
      else
        {:error, :invalid_token}
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:unsubscribed, true)
         |> YscWeb.Flash.put_toast(
           :info,
           "You have been unsubscribed from our newsletter.",
           title: "Newsletter"
         )}

      {:error, _} ->
        # Always show a safe message; never crash. User can use contact or try again.
        {:noreply,
         socket
         |> assign(
           :error,
           "We couldn't unsubscribe you right now. Please try again in a few minutes, or email info@ysc.org if you still receive newsletters."
         )
         |> YscWeb.Flash.put_toast(
           :error,
           "We couldn't unsubscribe you right now. Please try again in a few minutes, or email info@ysc.org if you still receive newsletters.",
           title: "Newsletter"
         )}
    end
  end
end
