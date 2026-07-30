defmodule QueryConsoleWeb.AuthController do
  use QueryConsoleWeb, :controller

  alias QueryConsole.Accounts
  alias QueryConsole.SSO
  alias QueryConsoleWeb.UserAuth

  def ysc(conn, _params) do
    {url, state, code_verifier} = SSO.build_authorize_url()

    conn
    |> put_session(:oauth_state, state)
    |> put_session(:oauth_code_verifier, code_verifier)
    |> redirect(external: url)
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    expected_state = get_session(conn, :oauth_state)
    code_verifier = get_session(conn, :oauth_code_verifier)

    cond do
      is_nil(expected_state) or state != expected_state ->
        conn
        |> put_flash(:error, "Invalid OAuth state")
        |> redirect(to: ~p"/auth/ysc")

      is_nil(code_verifier) ->
        conn
        |> put_flash(:error, "Missing PKCE verifier")
        |> redirect(to: ~p"/auth/ysc")

      true ->
        conn = conn |> delete_session(:oauth_state) |> delete_session(:oauth_code_verifier)

        with {:ok, claims} <- SSO.exchange_code(code, code_verifier),
             {:ok, user} <- Accounts.upsert_from_sso(claims) do
          conn
          |> UserAuth.log_in_user(user)
          # clear_session in log_in_user does not clear assigns.flash already
          # loaded by fetch_live_flash (e.g. leftover auth-gate messages).
          |> clear_flash()
          |> put_flash(:info, "Signed in as #{user.email}")
          |> redirect(to: ~p"/")
        else
          {:error, :not_admin} ->
            conn
            |> put_flash(:error, "Only YSC admins can use the query console.")
            |> redirect(to: ~p"/auth/signed-out")

          {:error, :not_active} ->
            conn
            |> put_flash(:error, "Your YSC account is not active.")
            |> redirect(to: ~p"/auth/signed-out")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Sign-in failed: #{inspect(reason)}")
            |> redirect(to: ~p"/auth/ysc")
        end
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Missing authorization code")
    |> redirect(to: ~p"/auth/ysc")
  end

  @doc """
  Clears the local query-console session, then front-channel logs out of YSC
  so SSO cannot silently sign the user back in.
  """
  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> redirect(external: SSO.build_logout_url())
  end

  def signed_out(conn, _params) do
    conn
    |> put_layout(html: false)
    |> render(:signed_out, page_title: "Signed out")
  end
end
