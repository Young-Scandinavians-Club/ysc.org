defmodule YscWeb.NewsletterSubscribe do
  @moduledoc """
  Shared guest-signup and member-toggle handlers for public newsletter forms.

  Used by the home page and newsletter archive LiveViews so rate limiting,
  Turnstile checks, confirmation emails, and toast copy stay in one place.

  ## Examples

      def handle_event("subscribe_newsletter", params, socket) do
        {:noreply, NewsletterSubscribe.request_guest(socket, params)}
      end

      def handle_event("toggle_newsletter_subscription", _params, socket) do
        {:noreply,
         NewsletterSubscribe.toggle_member(socket, source: "home_dashboard")}
      end
  """

  alias Ysc.Newsletter
  alias Ysc.NewsletterRateLimit

  @rate_limited_message "Too many subscription attempts. Please try again later."
  @turnstile_message "Please complete the verification to continue."
  @invalid_email_message "Please enter a valid email address."
  @no_mx_message "This email domain appears to be invalid. Please check your email address."

  @disposable_message "Temporary email addresses are not allowed. Please use a permanent email address."

  @generic_message "We couldn't subscribe you right now. Please try again later, or email info@ysc.org if this keeps happening."

  @toggle_error_message "We couldn't update your newsletter subscription. Please try again, or email info@ysc.org if this keeps happening."

  @doc """
  Returns whether the given email or user currently has an active subscription.
  """
  def subscribed?(nil), do: false

  def subscribed?(%{email: email}), do: subscribed?(email)

  def subscribed?(email) when is_binary(email) do
    case Newsletter.get_subscriber_by_email(email) do
      %{subscribed: true} -> true
      _ -> false
    end
  end

  @doc """
  Human-readable error for a failed guest signup attempt.
  """
  def guest_error(:invalid_email), do: @invalid_email_message
  def guest_error(:no_mx_records), do: @no_mx_message
  def guest_error(:disposable_email), do: @disposable_message
  def guest_error(:rate_limited), do: @rate_limited_message
  def guest_error(:turnstile), do: @turnstile_message

  def guest_error(%Ecto.Changeset{} = changeset) do
    case changeset.errors do
      [{:email, {msg, _}} | _] -> msg
      _ -> @generic_message
    end
  end

  def guest_error(_), do: @generic_message

  @doc """
  Processes a guest `subscribe_newsletter` form submit.

  Expects `socket.assigns.remote_ip` and writes `:newsletter_email`,
  `:newsletter_submitted`, and `:newsletter_error`.
  """
  @dialyzer {:nowarn_function, request_guest: 2}
  def request_guest(socket, params) when is_map(params) do
    email = params["email"]

    case NewsletterRateLimit.check(socket.assigns.remote_ip, email) do
      :ok ->
        verify_and_subscribe(socket, params, email)

      {:error, :rate_limited, _retry_after} ->
        assign_guest_error(socket, email, guest_error(:rate_limited))
    end
  end

  @doc """
  Toggles the current user's newsletter subscription.

  Options:

    * `:source` — required subscribe source string (e.g. `"home_dashboard"`)
    * `:assign` — boolean assign to flip (default `:newsletter_subscribed`)
  """
  def toggle_member(socket, opts) when is_list(opts) do
    assign_key = Keyword.get(opts, :assign, :newsletter_subscribed)
    source = Keyword.fetch!(opts, :source)
    user = socket.assigns.current_user
    currently_subscribed? = Map.fetch!(socket.assigns, assign_key)

    result =
      if currently_subscribed? do
        Newsletter.unsubscribe(user.email)
      else
        Newsletter.subscribe(user.email,
          user_id: user.id,
          first_name: user.first_name,
          last_name: user.last_name,
          source: source
        )
      end

    case result do
      {:ok, _} ->
        now_subscribed? = !currently_subscribed?
        {title, body} = toggle_toast(now_subscribed?)

        socket
        |> Phoenix.Component.assign(assign_key, now_subscribed?)
        |> YscWeb.Flash.put_toast(:info, body,
          title: title,
          icon: &YscWeb.CoreComponents.flash_toast_icon_success/1
        )

      {:error, _} ->
        Phoenix.LiveView.put_flash(socket, :error, @toggle_error_message)
    end
  end

  defp verify_and_subscribe(socket, params, email) do
    if Map.has_key?(params, "cf-turnstile-response") do
      case Turnstile.verify(params, socket.assigns.remote_ip) do
        {:ok, _} ->
          subscribe_guest(socket, email)

        {:error, _} ->
          socket
          |> assign_guest_error(email, guest_error(:turnstile))
          |> Turnstile.refresh()
      end
    else
      subscribe_guest(socket, email)
    end
  end

  defp subscribe_guest(socket, email) do
    metadata = %{"signup_date" => DateTime.utc_now() |> DateTime.to_iso8601()}

    case Newsletter.request_confirmation(email,
           source: "public_signup",
           metadata: metadata
         ) do
      {:ok, status} when status in [:pending, :already_subscribed] ->
        socket
        |> Phoenix.Component.assign(
          newsletter_email: email,
          newsletter_submitted: true,
          newsletter_error: nil
        )
        |> YscWeb.Flash.put_toast(
          :info,
          "Check your email to confirm your subscription.",
          title: "Almost there!",
          icon: &YscWeb.CoreComponents.flash_toast_icon_success/1
        )

      {:error, reason} ->
        assign_guest_error(socket, email, guest_error(reason))
    end
  end

  defp assign_guest_error(socket, email, message) do
    Phoenix.Component.assign(socket,
      newsletter_email: email,
      newsletter_error: message
    )
  end

  defp toggle_toast(true),
    do: {"Subscribed!", "You'll receive future newsletters in your inbox."}

  defp toggle_toast(false),
    do: {"Unsubscribed", "You won't receive newsletters anymore."}
end
