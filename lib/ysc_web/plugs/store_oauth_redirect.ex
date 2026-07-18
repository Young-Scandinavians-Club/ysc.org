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
    conn = UserAuth.clear_reauth_session(conn)

    if UserAuth.valid_internal_redirect?(redirect_to) do
      put_session(conn, :oauth_redirect_to, redirect_to)
    else
      conn
    end
  end

  defp store_redirect(conn) do
    UserAuth.clear_reauth_session(conn)
  end
end
