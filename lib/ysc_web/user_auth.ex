defmodule YscWeb.UserAuth do
  @moduledoc """
  Authentication and authorization functions for web requests.

  Handles user sign-in, sign-out, session management, and authentication plugs.
  """
  use YscWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Ysc.Accounts
  alias Ysc.Accounts.AuthService
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Subscriptions
  alias YscWeb.AccountSetupAccess

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_ysc_web_user_remember_me"

  defp remember_me_options do
    # In production (no code_reloader), use secure cookie; in dev allow HTTP
    secure = Application.get_env(:ysc, YscWeb.Endpoint)[:code_reloader] != true

    [
      sign: true,
      max_age: @max_age,
      same_site: "Lax",
      http_only: true,
      secure: secure
    ]
  end

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

    conn =
      conn
      |> renew_session()
      |> put_token_in_session(token)
      |> put_session(
        :reauth_verified_at,
        DateTime.utc_now() |> DateTime.to_unix()
      )
      |> maybe_write_remember_me_cookie(token, params)

    # Log sign-in after session is set so auth_events.session_id is populated (for "Current session" on Security page)
    AuthService.log_login_success(user, conn, params)

    redirect(conn, to: post_login_redirect(user, conn, validated_redirect))
  end

  # Post-login destination: onboarding wins over redirect_to / return_to, then account setup, etc.
  defp post_login_redirect(user, conn, validated_redirect) do
    cond do
      Accounts.needs_post_migration_onboarding?(user) ->
        ~p"/onboarding"

      validated_redirect ->
        validated_redirect

      true ->
        signed_in_path_for_user(user, conn)
    end
  end

  # Default signed-in path when no explicit redirect_to / user_return_to is provided.
  defp signed_in_path_for_user(user, conn) do
    cond do
      Accounts.needs_post_migration_onboarding?(user) ->
        ~p"/onboarding"

      is_nil(user.email_verified_at) ->
        AccountSetupAccess.setup_path(user.id)

      user.state == :pending_approval ->
        ~p"/pending-review"

      true ->
        signed_in_path(conn)
    end
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, remember_me_options())
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
  Returns the LiveView socket topic ID for a session given its encoded session ID
  (Base64, as stored in auth_events). Used when revoking a session so we can
  broadcast "disconnect" and close any persistent LiveView connections for that session.
  """
  def live_socket_id_from_encoded_session(encoded_session_id)
      when is_binary(encoded_session_id) do
    case Base.decode64(encoded_session_id) do
      {:ok, token} -> "users_sessions:#{Base.url_encode64(token)}"
      :error -> nil
    end
  end

  def live_socket_id_from_encoded_session(_), do: nil

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn, redirect_to \\ nil) do
    redirect_path =
      if redirect_to && valid_internal_redirect?(redirect_to) do
        redirect_to
      else
        ~p"/"
      end

    conn
    |> drop_user_session()
    |> redirect(to: redirect_path)
  end

  @doc """
  Clears the authenticated session and remember-me cookie without redirecting.

  Used by first-party OAuth logout where the browser is then sent to an
  allowlisted external `post_logout_redirect_uri`.
  """
  def drop_user_session(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      YscWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
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
        |> YscWeb.Flash.put_toast(
          :error,
          "You must sign in to access this page.",
          title: "Sign in required"
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

    if admin_user && admin_user.role in [:admin, :volunteer] do
      {:cont, Phoenix.Component.assign(socket, :admin_role, admin_user.role)}
    else
      socket =
        socket
        |> YscWeb.Flash.put_toast(
          :error,
          "You do not have permission to access this page",
          title: "Access denied"
        )
        |> Phoenix.LiveView.redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  def on_mount(:ensure_full_admin, _params, _session, socket) do
    admin_user =
      socket.assigns[:real_current_user] || socket.assigns.current_user

    if admin_user && admin_user.role == :admin do
      {:cont, socket}
    else
      socket =
        socket
        |> YscWeb.Flash.put_toast(
          :error,
          "You do not have permission to access this page",
          title: "Access denied"
        )
        |> Phoenix.LiveView.redirect(to: ~p"/admin")

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
        |> YscWeb.Flash.put_toast(
          :error,
          "Your membership application is still under review. We'll email you when the board has made a decision.",
          title: "Account"
        )
        |> Phoenix.LiveView.redirect(to: ~p"/pending-review")

      {:halt, socket}
    end
  end

  def on_mount(:ensure_onboarding_complete, _params, _session, socket) do
    user = socket.assigns[:current_user]

    if user && Accounts.needs_post_migration_onboarding?(user) do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/onboarding")}
    else
      {:cont, socket}
    end
  end

  @reauth_ttl_seconds 300

  def on_mount(:mount_reauth_session, _params, session, socket) do
    timestamp = session["reauth_verified_at"]

    # Compute the absolute expiry so handlers can re-check at action time
    # rather than relying on a boolean that was frozen at mount.
    expires_at =
      case timestamp do
        ts when is_integer(ts) -> ts + @reauth_ttl_seconds
        _ -> nil
      end

    verified =
      case expires_at do
        ts when is_integer(ts) -> ts > DateTime.utc_now() |> DateTime.to_unix()
        _ -> false
      end

    {:cont,
     socket
     |> Phoenix.Component.assign_new(:session_reauth_verified, fn ->
       verified
     end)
     |> Phoenix.Component.assign_new(:session_reauth_expires_at, fn ->
       expires_at
     end)}
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
    user_token = session["user_token"]

    user_from_token =
      if user_token, do: Accounts.get_user_by_session_token(user_token)

    # Encode session token for comparison with auth_events.session_id (used on Security page)
    current_session_id =
      if is_binary(user_token), do: Base.encode64(user_token), else: nil

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
      |> Phoenix.Component.assign_new(:current_session_id, fn ->
        current_session_id
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

    socket =
      Phoenix.Component.assign_new(socket, :had_membership?, fn ->
        # Default false on every LiveView. EventDetailsLive computes the real
        # value (expired vs never-subscribed copy) only when a logged-in user
        # has no active membership — avoid `list_subscriptions/1` on all pages.
        false
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
      |> YscWeb.Flash.put_toast(:error, "You must sign in to access this page.",
        title: "Sign in required"
      )
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  @doc """
  Used for routes that require the user to have completed post-migration onboarding.
  Redirects to /onboarding if the user still has pending onboarding.
  """
  def require_onboarding_complete(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && Accounts.needs_post_migration_onboarding?(user) do
      conn
      |> redirect(to: ~p"/onboarding")
      |> halt()
    else
      conn
    end
  end

  def require_admin(conn, _opts) do
    user = conn.assigns[:real_current_user] || conn.assigns[:current_user]

    if user && user.role in [:admin, :volunteer] do
      conn
    else
      conn
      |> YscWeb.Flash.put_toast(
        :error,
        "You do not have permission to access this page.",
        title: "Access denied"
      )
      |> maybe_store_return_to()
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  def require_full_admin(conn, _opts) do
    user = conn.assigns[:real_current_user] || conn.assigns[:current_user]

    if user && user.role == :admin do
      conn
    else
      conn
      |> YscWeb.Flash.put_toast(
        :error,
        "You do not have permission to access this page.",
        title: "Access denied"
      )
      |> redirect(to: ~p"/admin")
      |> halt()
    end
  end

  def require_approved(conn, _opts) do
    user = conn.assigns[:current_user]

    if user.state == :active do
      conn
    else
      conn
      |> YscWeb.Flash.put_toast(
        :error,
        "Your membership application is still under review. We'll email you when the board has made a decision.",
        title: "Account"
      )
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
      cond do
        Accounts.needs_post_migration_onboarding?(user) -> ~p"/onboarding"
        user.state == :pending_approval -> ~p"/pending-review"
        true -> ~p"/"
      end
    else
      ~p"/"
    end
  end

  defp signed_in_path(socket) do
    if user = socket.assigns[:current_user] do
      cond do
        Accounts.needs_post_migration_onboarding?(user) -> ~p"/onboarding"
        user.state == :pending_approval -> ~p"/pending-review"
        true -> ~p"/"
      end
    else
      ~p"/"
    end
  end

  defp not_approved_path(_conn), do: ~p"/pending-review"

  # Paths that may include nested absolute URLs in the query string after login
  # (e.g. OAuth authorize `redirect_uri=https://…`). Everything else still rejects
  # `://` / `//` anywhere in the return_to value.
  @return_to_paths_allowing_nested_urls [
    "/oauth/authorize",
    "/oauth/query-console/authorize"
  ]

  @doc """
  Validates that a redirect URL is an internal path and not an external URL.

  This prevents open redirect vulnerabilities by ensuring redirects only go to
  paths within the application, not to external websites.

  Nested absolute URLs in the query string are rejected by default. A small
  allowlist of first-party OAuth authorize paths may include them (the
  destination still validates `redirect_uri` against its own client allowlist).

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
    normalized = repeatedly_percent_decode_redirect_target(path)

    case URI.parse(normalized) do
      %URI{scheme: nil, host: nil, path: path_part} = uri
      when is_binary(path_part) and path_part != "" ->
        cond do
          not String.starts_with?(path_part, "/") ->
            false

          path_part in @return_to_paths_allowing_nested_urls ->
            # Allow nested URLs in the query; still forbid them in path/fragment.
            not dangerous_redirect_path_or_fragment?(path_part, uri.fragment)

          contains_dangerous_redirect_token?(normalized) ->
            false

          true ->
            true
        end

      %URI{scheme: scheme} when not is_nil(scheme) ->
        false

      %URI{host: host} when not is_nil(host) ->
        false

      _ ->
        false
    end
  end

  def valid_internal_redirect?(_), do: false

  defp contains_dangerous_redirect_token?(value) do
    String.contains?(value, [
      "//",
      "javascript:",
      "data:",
      "vbscript:",
      "://",
      # Browsers strip ASCII tab/CR/LF when parsing a URL, so "/\t/evil.com"
      # becomes "//evil.com" client-side even though it lacks a literal "//"
      # here (CVE-2026-64941 / EEF-CVE-2026-64941 style bypass).
      "\t",
      "\n",
      "\r"
    ])
  end

  defp dangerous_redirect_path_or_fragment?(path_part, fragment) do
    contains_dangerous_redirect_token?(path_part <> (fragment || ""))
  end

  @doc """
  Clears OAuth re-authentication flags from the plug session.

  Removes keys set during sensitive flows when the user starts a normal OAuth
  sign-in or when a re-authentication attempt finishes or fails, so stale
  flags cannot affect later requests.
  """
  def clear_reauth_session(conn) do
    conn
    |> delete_session(:reauth_mode)
    |> delete_session(:reauth_return_to)
  end

  # Decode percent-encoding repeatedly so "%252f" (encoded "%2f") cannot hide protocol-relative URLs.
  defp repeatedly_percent_decode_redirect_target(path, iterations \\ 0)

  defp repeatedly_percent_decode_redirect_target(path, 12), do: path

  defp repeatedly_percent_decode_redirect_target(path, iterations) do
    decoded =
      try do
        URI.decode(path)
      rescue
        ArgumentError -> path
      end

    if decoded == path do
      path
    else
      repeatedly_percent_decode_redirect_target(decoded, iterations + 1)
    end
  end

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
        membership_plan_label(plan_id)
    end
  end

  def get_membership_plan_display_name(%{plan: %{id: plan_id}})
      when not is_nil(plan_id) do
    membership_plan_label(plan_id)
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
        Ysc.Text.titleize(plan_id)
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

  defp membership_plan_label(plan_id),
    do: "#{Ysc.Text.titleize(plan_id)} Membership"
end
