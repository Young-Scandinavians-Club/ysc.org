defmodule YscWeb.UserAuth do
  @moduledoc """
  Authentication and authorization functions for web requests.

  Handles user sign-in, sign-out, session management, and authentication plugs.
  """
  use YscWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Ysc.Accounts
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Subscriptions

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_ysc_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on sign out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}, redirect_to \\ nil) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    # Validate redirect_to if provided
    validated_redirect =
      cond do
        redirect_to && valid_internal_redirect?(redirect_to) ->
          redirect_to

        user_return_to && valid_internal_redirect?(user_return_to) ->
          user_return_to

        true ->
          nil
      end

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: validated_redirect || signed_in_path_for_user(user, conn))
  end

  # Get the appropriate signed-in path for a user
  defp signed_in_path_for_user(user, conn) do
    cond do
      is_nil(user.email_verified_at) ->
        # User hasn't verified email, redirect to account setup
        ~p"/account/setup/#{user.id}"

      user.state == :pending_approval ->
        ~p"/pending-review"

      true ->
        signed_in_path(conn)
    end
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after sign in/sign out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    # Preserve just_logged_in flag through session renewal
    just_logged_in = get_session(conn, :just_logged_in)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> then(fn conn ->
      if just_logged_in do
        put_session(conn, :just_logged_in, just_logged_in)
      else
        conn
      end
    end)
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      YscWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)

    user_from_token =
      user_token && Accounts.get_user_by_session_token(user_token)

    impersonated_user_id = get_session(conn, :impersonated_user_id)

    {current_user, conn} =
      if impersonated_user_id do
        impersonated = Accounts.get_user(impersonated_user_id)
        conn = assign(conn, :real_current_user, user_from_token)
        {impersonated, assign(conn, :current_user, impersonated)}
      else
        {user_from_token, assign(conn, :current_user, user_from_token)}
      end

    conn =
      conn
      |> assign(:impersonating?, impersonated_user_id != nil)
      |> assign(:original_admin_id, get_session(conn, :original_admin_id))

    if current_user do
      active_membership = MembershipCache.get_active_membership(current_user)

      conn
      |> assign(:current_membership, active_membership)
      |> assign(:active_membership?, active_membership != nil)
    else
      conn
      |> assign(:current_membership, nil)
      |> assign(:active_membership?, false)
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to sign-in page if there's no signed-in user.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a signed-in user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule YscWeb.PageLive do
        use YscWeb, :live_view

        on_mount {YscWeb.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{YscWeb.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    socket = mount_current_user(socket, session)
    {:cont, mount_current_membership(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          "You must sign in to access this page."
        )
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    admin_user =
      socket.assigns[:real_current_user] || socket.assigns.current_user

    if admin_user && admin_user.role == :admin do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          "You do not have permission to access this page"
        )
        |> Phoenix.LiveView.redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  def on_mount(:ensure_active, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    user = socket.assigns.current_user

    if user && user.state == :active do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Your account is not active")
        |> Phoenix.LiveView.redirect(to: ~p"/pending-review")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  def on_mount(
        :redirect_if_user_is_authenticated_and_pending_approval,
        _params,
        session,
        socket
      ) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    if socket.assigns.current_user do
      if socket.assigns.current_user.state == "pending_approval" do
        {:halt,
         Phoenix.LiveView.redirect(socket, to: not_approved_path(socket))}
      else
        {:cont, socket}
      end
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    user_from_token =
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end

    impersonated_user_id = session["impersonated_user_id"]

    socket =
      socket
      |> Phoenix.Component.assign_new(:real_current_user, fn ->
        user_from_token
      end)
      |> Phoenix.Component.assign_new(:current_user, fn ->
        if impersonated_user_id do
          Accounts.get_user(impersonated_user_id)
        else
          user_from_token
        end
      end)
      |> Phoenix.Component.assign_new(:impersonating?, fn ->
        impersonated_user_id != nil
      end)
      |> Phoenix.Component.assign_new(:original_admin_id, fn ->
        session["original_admin_id"]
      end)

    socket
  end

  defp mount_current_membership(socket, _session) do
    socket =
      Phoenix.Component.assign_new(socket, :current_membership, fn ->
        if socket.assigns.current_user != nil do
          MembershipCache.get_active_membership(socket.assigns.current_user)
        end
      end)

    Phoenix.Component.assign_new(socket, :active_membership?, fn ->
      socket.assigns.current_membership != nil
    end)
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must sign in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  def require_admin(conn, _opts) do
    user = conn.assigns[:real_current_user] || conn.assigns[:current_user]

    if user && user.role == :admin do
      conn
    else
      conn
      |> put_flash(:error, "You do not have permission to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  def require_approved(conn, _opts) do
    user = conn.assigns[:current_user]

    if user.state == :active do
      conn
    else
      conn
      |> put_flash(:error, "Your account has not been approved yet")
      |> redirect(to: ~p"/pending-review")
      |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(
      :live_socket_id,
      "users_sessions:#{Base.url_encode64(token)}"
    )
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(%Plug.Conn{} = conn) do
    if user = conn.assigns[:current_user] do
      case user.state do
        :pending_approval -> ~p"/pending-review"
        _ -> ~p"/"
      end
    else
      ~p"/"
    end
  end

  defp signed_in_path(socket) do
    if user = socket.assigns[:current_user] do
      case user.state do
        :pending_approval -> ~p"/pending-review"
        _ -> ~p"/"
      end
    else
      ~p"/"
    end
  end

  defp not_approved_path(_conn), do: ~p"/pending-review"

  @doc """
  Validates that a redirect URL is an internal path and not an external URL.

  This prevents open redirect vulnerabilities by ensuring redirects only go to
  paths within the application, not to external websites.

  ## Examples

      iex> valid_internal_redirect?("/events/123")
      true

      iex> valid_internal_redirect?("/users/settings")
      true

      iex> valid_internal_redirect?("https://evil.com")
      false

      iex> valid_internal_redirect?("//evil.com")
      false

      iex> valid_internal_redirect?("javascript:alert(1)")
      false
  """
  def valid_internal_redirect?(path) when is_binary(path) do
    # First check for dangerous patterns in the raw string
    if String.contains?(path, ["//", "javascript:", "data:", "vbscript:", "://"]) do
      false
    else
      # Parse the path to check if it's a valid URI
      case URI.parse(path) do
        # Must be a relative path (no scheme, no host)
        %URI{scheme: nil, host: nil, path: path_part} when is_binary(path_part) ->
          # Check that path starts with / (relative internal path)
          String.starts_with?(path_part, "/")

        # Reject any URI with a scheme (http://, https://, etc.)
        %URI{scheme: scheme} when not is_nil(scheme) ->
          false

        # Reject any URI with a host (external domain)
        %URI{host: host} when not is_nil(host) ->
          false

        # Reject malformed URIs or empty paths
        _ ->
          false
      end
    end
  end

  def valid_internal_redirect?(_), do: false

  @doc """
  Checks if a membership is active.

  Returns `true` if the membership is active, `false` otherwise.

  ## Examples

      iex> membership_active?(nil)
      false

      iex> membership_active?(%{type: :lifetime})
      true

      iex> membership_active?(%Ysc.Subscriptions.Subscription{stripe_status: "active"})
      true
  """
  def membership_active?(nil), do: false
  def membership_active?(%{type: :lifetime}), do: true

  def membership_active?(%Ysc.Subscriptions.Subscription{} = subscription),
    do: Subscriptions.valid?(subscription)

  def membership_active?(_), do: false

  @doc """
  Gets the plan type from a membership.

  Returns the plan ID as an atom (`:lifetime`, `:single`, `:family`, etc.) or `nil`.

  ## Examples

      iex> get_membership_plan_type(nil)
      nil

      iex> get_membership_plan_type(%{type: :lifetime})
      :lifetime

      iex> get_membership_plan_type(%Ysc.Subscriptions.Subscription{...})
      :family
  """
  def get_membership_plan_type(nil), do: nil
  def get_membership_plan_type(%{type: :lifetime}), do: :lifetime

  def get_membership_plan_type(%Ysc.Subscriptions.Subscription{} = subscription) do
    subscription = Ysc.Repo.preload(subscription, :subscription_items)

    case subscription.subscription_items do
      [item | _] ->
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        case Enum.find(
               membership_plans,
               &(&1.stripe_price_id == item.stripe_price_id)
             ) do
          %{id: plan_id} when not is_nil(plan_id) -> plan_id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def get_membership_plan_type(%{plan: %{id: plan_id}})
      when not is_nil(plan_id), do: plan_id

  def get_membership_plan_type(_), do: nil

  @doc """
  Gets the renewal or end date for a membership.

  For lifetime memberships, returns `nil` (never expires).
  For subscriptions, returns the `current_period_end` DateTime.

  ## Examples

      iex> get_membership_renewal_date(nil)
      nil

      iex> get_membership_renewal_date(%{type: :lifetime})
      nil

      iex> get_membership_renewal_date(%Ysc.Subscriptions.Subscription{current_period_end: ~U[2026-12-29 15:40:25Z]})
      ~U[2026-12-29 15:40:25Z]
  """
  def get_membership_renewal_date(nil), do: nil
  def get_membership_renewal_date(%{type: :lifetime}), do: nil

  def get_membership_renewal_date(
        %Ysc.Subscriptions.Subscription{} = subscription
      ),
      do: subscription.current_period_end

  def get_membership_renewal_date(%{renewal_date: renewal_date})
      when not is_nil(renewal_date),
      do: renewal_date

  def get_membership_renewal_date(_), do: nil

  @doc """
  Gets a formatted display name for the membership.

  Returns a human-readable string like "Lifetime Membership", "Single Membership", "Family Membership", etc.

  ## Examples

      iex> get_membership_plan_display_name(nil)
      "No Membership"

      iex> get_membership_plan_display_name(%{type: :lifetime})
      "Lifetime Membership"

      iex> get_membership_plan_display_name(%Ysc.Subscriptions.Subscription{...})
      "Family Membership"
  """
  def get_membership_plan_display_name(nil), do: "No Membership"

  def get_membership_plan_display_name(%{type: :lifetime}),
    do: "Lifetime Membership"

  def get_membership_plan_display_name(
        %Ysc.Subscriptions.Subscription{} = subscription
      ) do
    case get_membership_plan_type(subscription) do
      nil ->
        "Active Membership"

      plan_id ->
        plan_id
        |> Atom.to_string()
        |> String.split("_")
        |> Enum.map_join(" ", &String.capitalize/1)
        |> then(&"#{&1} Membership")
    end
  end

  def get_membership_plan_display_name(%{plan: %{id: plan_id}})
      when not is_nil(plan_id) do
    plan_id
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
    |> then(&"#{&1} Membership")
  end

  def get_membership_plan_display_name(_), do: "Active Membership"

  @doc """
  Gets the membership plan type for a user.

  This is a convenience function that gets the active membership for a user
  and returns the plan type. Use this when you have a User object instead
  of a membership struct.

  This function uses caching with a 5-minute TTL to reduce database queries.

  ## Examples

      iex> get_user_membership_plan_type(user)
      :family

      iex> get_user_membership_plan_type(user_with_no_membership)
      nil
  """
  def get_user_membership_plan_type(user) when is_nil(user), do: nil

  def get_user_membership_plan_type(user) do
    MembershipCache.get_membership_plan_type(user)
  end

  @doc """
  Gets a formatted membership type string for display.

  Returns a capitalized string like "Lifetime", "Single", "Family", etc.

  ## Examples

      iex> get_membership_type_display_string(nil)
      "Unknown"

      iex> get_membership_type_display_string(%{type: :lifetime})
      "Lifetime"

      iex> get_membership_type_display_string(%Ysc.Subscriptions.Subscription{...})
      "Family"
  """
  def get_membership_type_display_string(nil), do: "Unknown"

  def get_membership_type_display_string(membership) do
    case get_membership_plan_type(membership) do
      nil ->
        "Unknown"

      plan_id ->
        plan_id
        |> Atom.to_string()
        |> String.split("_")
        |> Enum.map_join(" ", &String.capitalize/1)
    end
  end

  @doc """
  Gets the active membership for a user.

  Returns the membership struct (lifetime map or subscription) or nil.
  For sub-accounts, checks the primary user's membership.

  This function uses caching with a 5-minute TTL to reduce database queries.

  ## Examples

      iex> get_active_membership(user)
      %Ysc.Subscriptions.Subscription{...}

      iex> get_active_membership(user_with_lifetime)
      %{type: :lifetime, ...}
  """
  def get_active_membership(user) do
    MembershipCache.get_active_membership(user)
  end
end
