defmodule YscWeb.EventNotificationUnsubscribeLive do
  @moduledoc """
  Public page for unsubscribing from event notification emails via a link in
  an email, without signing in.

  Route: `/event-notifications/unsubscribe/:token`

  The `:token` path param is verified with
  `Ysc.Accounts.EventNotificationUnsubscribeToken`, which resolves it to a
  `user_id` only if it was signed by this app. `handle_event/3` always
  unsubscribes the user resolved at mount, never a raw URL value.
  """
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.EventNotificationUnsubscribeToken
  alias Ysc.Accounts.User

  @impl true
  def mount(%{"token" => token} = _params, _session, socket) do
    user = safe_get_user_by_token(token)

    # Show success state if already unsubscribed (idempotent: safe to reload link)
    unsubscribed = user != nil && !user.event_notifications

    socket =
      socket
      |> assign(:page_title, "Unsubscribe from Event Notifications")
      |> assign(
        :meta_description,
        "Unsubscribe from Young Scandinavians Club event notifications."
      )
      |> assign(:user, user)
      |> assign(:unsubscribed, unsubscribed)

    {:ok, socket}
  end

  defp safe_get_user_by_token(token) when is_binary(token) do
    with true <- String.trim(token) != "",
         {:ok, user_id} <- EventNotificationUnsubscribeToken.verify(token) do
      Accounts.get_user(user_id)
    else
      _ -> nil
    end
  end

  defp safe_get_user_by_token(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <.unsubscribe_page
      id="event-notification-unsubscribe-page"
      email={@user && @user.email}
      unsubscribed={@unsubscribed}
      subscribed_title="Unsubscribe from event notifications"
      subscribed_action="event notification emails"
      unsubscribed_body="You will no longer receive event notification emails. You can turn them back on anytime from your notification settings."
      still_receive="event notifications"
    />
    """
  end

  @impl true
  def handle_event("unsubscribe", _params, socket) do
    # This page is public. Mount resolves the user by verified token only, so
    # the unsubscribe action always acts on that resolved user, never a raw
    # URL value.
    user = socket.assigns.user

    result =
      if user do
        Accounts.disable_event_notifications(user.email)
      else
        {:error, :invalid_token}
      end

    case result do
      {:ok, status} when status in [:already_disabled] ->
        {:noreply, socket |> assign(:unsubscribed, true)}

      {:ok, %User{}} ->
        {:noreply,
         socket
         |> assign(:unsubscribed, true)
         |> YscWeb.Flash.put_toast(
           :info,
           "You have been unsubscribed from event notifications.",
           title: "Notifications"
         )}

      _ ->
        # Always show a safe message; never crash. User can use contact or try again.
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "We couldn't unsubscribe you right now. Please try again in a few minutes, or email info@ysc.org if you still receive event notifications.",
           title: "Notifications"
         )}
    end
  end
end
