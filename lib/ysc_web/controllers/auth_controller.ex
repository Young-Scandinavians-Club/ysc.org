defmodule YscWeb.AuthController do
  @moduledoc """
  Controller for handling OAuth authentication flows.
  """
  use YscWeb, :controller

  plug YscWeb.Plugs.StoreOAuthRedirect
  plug Ueberauth

  alias Ysc.Accounts
  alias Ysc.Accounts.Email
  alias YscWeb.UserAuth

  @doc """
  OAuth request phase entry point. Ueberauth handles the provider redirect;
  `YscWeb.Plugs.StoreOAuthRedirect` stores `redirect_to` / reauth metadata in session.
  """
  def request(conn, _params), do: conn

  @doc """
  Handles OAuth callback phase for Google authentication.
  """
  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    # User cancelled or OAuth provider returned an error — clear any stale reauth flags
    conn
    |> UserAuth.clear_reauth_session()
    |> YscWeb.Flash.put_toast(
      :error,
      "Authentication was cancelled or failed. Please try again.",
      title: "Authentication"
    )
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    email = extract_email(auth)
    image_url = extract_image(auth)

    if email do
      if get_session(conn, :reauth_mode) do
        handle_oauth_reauth(conn, email)
      else
        handle_oauth_success(conn, email, auth.provider, image_url)
      end
    else
      conn
      |> UserAuth.clear_reauth_session()
      |> YscWeb.Flash.put_toast(
        :error,
        "Unable to retrieve email from your account. Please email #{Ysc.EmailConfig.contact_email()} for help.",
        title: "Authentication"
      )
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(conn, _params) do
    # Unexpected state - no auth and no failure — clear any stale reauth flags
    conn
    |> UserAuth.clear_reauth_session()
    |> YscWeb.Flash.put_toast(
      :error,
      "Authentication error occurred. Please try again.",
      title: "Authentication"
    )
    |> redirect(to: ~p"/users/log-in")
  end

  # Private helper functions

  defp handle_oauth_reauth(conn, oauth_email) do
    return_to = get_session(conn, :reauth_return_to) || "/"

    user_token = get_session(conn, :user_token)

    current_user =
      if user_token, do: Accounts.get_user_by_session_token(user_token)

    cond do
      is_nil(current_user) ->
        conn
        |> UserAuth.clear_reauth_session()
        |> YscWeb.Flash.put_toast(
          :error,
          "Session expired. Please sign in again.",
          title: "Authentication"
        )
        |> redirect(to: ~p"/users/log-in")

      Email.equiv?(oauth_email, current_user.email) ->
        conn
        |> UserAuth.clear_reauth_session()
        |> put_session(
          :reauth_verified_at,
          DateTime.utc_now() |> DateTime.to_unix()
        )
        |> YscWeb.Flash.put_toast(:info, "Identity verified successfully.",
          title: "Verification"
        )
        |> redirect(to: return_to)

      true ->
        conn
        |> UserAuth.clear_reauth_session()
        |> YscWeb.Flash.put_toast(
          :error,
          "The social account email doesn't match your account. Please use the social account associated with your registered email.",
          title: "Verification failed"
        )
        |> redirect(to: return_to)
    end
  end

  defp extract_email(%Ueberauth.Auth{info: info}) do
    info.email || info.raw["email"] || info.raw["emailAddress"]
  end

  defp extract_image(%Ueberauth.Auth{provider: :google, info: %{image: image}})
       when is_binary(image) and image != "" do
    # Google userinfo returns URLs with a small size suffix like `=s96-c`.
    # Strip it to request the original full-resolution image instead.
    url = Regex.replace(~r/=s\d+-c$/, image, "=s0-c")
    if safe_image_url?(url), do: url, else: nil
  end

  defp extract_image(%Ueberauth.Auth{info: %{image: image}})
       when is_binary(image) and image != "" do
    if safe_image_url?(image), do: image, else: nil
  end

  defp extract_image(_), do: nil

  # Validates that a URL is safe to fetch: must be HTTPS and must not point to
  # localhost, loopback, link-local, or private RFC-1918 address ranges.
  defp safe_image_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        not private_host?(host)

      _ ->
        false
    end
  end

  @private_prefixes ["10.", "192.168.", "169.254.", "0."]
  @loopback_hosts ["localhost", "127.0.0.1", "::1", "[::1]"]

  defp private_host?(host) do
    host = String.downcase(host)

    host in @loopback_hosts or
      String.ends_with?(host, ".localhost") or
      Enum.any?(@private_prefixes, &String.starts_with?(host, &1)) or
      match_172_private?(host)
  end

  defp match_172_private?(host) do
    case String.split(host, ".") do
      ["172", second | _] ->
        case Integer.parse(second) do
          {n, ""} when n >= 16 and n <= 31 -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp handle_oauth_success(conn, email, provider, image_url) do
    case Accounts.get_user_by_email(email) do
      nil ->
        # User doesn't exist - use generic message to avoid user enumeration
        conn
        |> YscWeb.Flash.put_toast(
          :error,
          "Unable to sign in. Please try again, or email #{Ysc.EmailConfig.contact_email()} for help.",
          title: "Authentication"
        )
        |> redirect(to: ~p"/users/log-in")

      user ->
        # Check if user is in an allowed state for login
        if user.state in [:pending_approval, :active] do
          # Set email_verified_at if not already set (OAuth providers verify emails)
          updated_user =
            if is_nil(user.email_verified_at) do
              case Accounts.mark_email_verified(user) do
                {:ok, updated} -> updated
                {:error, _} -> user
              end
            else
              user
            end

          # Sync OAuth profile image asynchronously (non-blocking).
          # Only :google/:facebook are supported by Avatars.sync_oauth_avatar/3;
          # other providers (e.g. :apple) don't expose a stable photo URL we sync.
          source = image_url && provider_to_avatar_source(provider)

          if source do
            Task.Supervisor.start_child(Ysc.TaskSupervisor, fn ->
              Ysc.Avatars.sync_oauth_avatar(updated_user, image_url, source)
            end)
          end

          # Get redirect_to from session if it was stored
          redirect_to = get_session(conn, :oauth_redirect_to)

          conn
          |> delete_session(:oauth_redirect_to)
          |> YscWeb.Flash.put_toast(
            :info,
            "Successfully signed in with #{String.capitalize(to_string(provider))}!",
            title: "Authentication"
          )
          |> put_session(:just_logged_in, true)
          |> UserAuth.log_in_user(
            updated_user,
            %{
              "method" => to_string(provider),
              "provider" => to_string(provider),
              "remember_me" => "true"
            },
            redirect_to
          )
        else
          # Account not in allowed state
          conn
          |> YscWeb.Flash.put_toast(
            :error,
            "Your account is not currently active.",
            title: "Authentication"
          )
          |> redirect(to: ~p"/users/log-in")
        end
    end
  end

  defp provider_to_avatar_source(:google), do: :google
  defp provider_to_avatar_source(:facebook), do: :facebook
  defp provider_to_avatar_source(_), do: nil
end
