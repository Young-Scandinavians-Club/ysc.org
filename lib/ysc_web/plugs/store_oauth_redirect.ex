defmodule YscWeb.Plugs.StoreOAuthRedirect do
  @moduledoc """
  Persists OAuth redirect targets in session before Ueberauth halts the request phase.

  Ueberauth redirects to the provider and halts the plug pipeline, so
  `AuthController.request/2` never runs. This plug must run before `plug Ueberauth`.
  """
  import Plug.Conn

  alias YscWeb.UserAuth

  @oauth_request_path ~r"^/auth/[^/]+$"

  def init(opts), do: opts

  def call(conn, _opts) do
    if oauth_request_path?(conn) do
      store_redirect(conn)
    else
      conn
    end
  end

  defp oauth_request_path?(%{request_path: path}) when is_binary(path) do
    Regex.match?(@oauth_request_path, path)
  end

  defp oauth_request_path?(_), do: false

  defp store_redirect(%{params: %{"reauth" => "true"} = params} = conn) do
    conn =
      conn
      |> delete_session(:oauth_redirect_to)
      |> UserAuth.clear_reauth_session()

    return_to = Map.get(params, "return_to", "/")

    if UserAuth.valid_internal_redirect?(return_to) do
      conn
      |> put_session(:reauth_mode, true)
      |> put_session(:reauth_return_to, return_to)
    else
      conn
    end
  end

  defp store_redirect(%{params: %{"redirect_to" => redirect_to}} = conn) do
    conn =
      conn
      |> delete_session(:oauth_redirect_to)
      |> UserAuth.clear_reauth_session()
      |> maybe_store_mobile_redirect_uri()

    if UserAuth.valid_internal_redirect?(redirect_to) do
      put_session(conn, :oauth_redirect_to, redirect_to)
    else
      conn
    end
  end

  defp store_redirect(conn) do
    conn
    |> delete_session(:oauth_redirect_to)
    |> UserAuth.clear_reauth_session()
    |> maybe_store_mobile_redirect_uri()
  end

  # Mobile app browser-handoff (see YscWeb.UserAuth.log_in_user/5). Ueberauth's
  # OAuth2 strategies don't round-trip arbitrary extra query params through
  # the provider and back, so — same as oauth_redirect_to above — this is
  # stashed in session before the provider redirect and read back in
  # AuthController's callback phase.
  defp maybe_store_mobile_redirect_uri(%{params: %{"mobile_redirect_uri" => uri}} = conn)
       when is_binary(uri) do
    conn = delete_session(conn, :oauth_mobile_redirect_uri)

    if UserAuth.valid_mobile_redirect_uri?(uri) do
      put_session(conn, :oauth_mobile_redirect_uri, uri)
    else
      conn
    end
  end

  defp maybe_store_mobile_redirect_uri(conn), do: delete_session(conn, :oauth_mobile_redirect_uri)
end
