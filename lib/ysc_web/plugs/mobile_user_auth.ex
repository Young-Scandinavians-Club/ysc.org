defmodule YscWeb.Plugs.MobileUserAuth do
  @moduledoc """
  Authenticates requests from the YSC admin/volunteer mobile app.

  Validates the Authorization header (Bearer <token>) against a per-user
  mobile session token (see `Ysc.Accounts.generate_user_mobile_token/1`),
  and requires the resolved user to have role :admin or :volunteer — the
  same split used by `YscWeb.UserAuth.require_admin/2` on the web admin
  panel. Assigns the user to `conn.assigns.current_user` on success.
  """
  import Plug.Conn

  alias Ysc.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with token when is_binary(token) <- extract_token(conn),
         %Accounts.User{} = user <- Accounts.get_user_by_mobile_token(token),
         true <- user.role in [:admin, :volunteer] do
      assign(conn, :current_user, user)
    else
      _ -> halt_unauthorized(conn)
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> String.trim(token)
      _ -> nil
    end
  end

  @doc """
  Returns `:ok` when the authenticated mobile-app user is a full admin.

  Volunteers share this API with admins for in-person card-present door
  sales, but unpaid honor-system actions (offline ticket grants and
  out-of-band memberships) must stay admin-only — the same split Findings
  46 and 50 enforce on the web Tickets tab.
  """
  def require_full_admin(conn) do
    case conn.assigns[:current_user] do
      %{role: :admin} -> :ok
      _ -> {:error, :full_admin_required}
    end
  end

  defp halt_unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
    |> halt()
  end
end
