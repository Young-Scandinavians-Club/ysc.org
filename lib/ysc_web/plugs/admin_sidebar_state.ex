defmodule YscWeb.Plugs.AdminSidebarState do
  @moduledoc false

  import Plug.Conn

  @cookie_name "admin_sb_collapsed"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    Plug.Conn.assign(conn, :sidebar_collapsed, sidebar_collapsed?(conn))
  end

  defp sidebar_collapsed?(conn) do
    case conn.query_params do
      %{"sidebar_collapsed" => "1"} -> true
      %{"sidebar_collapsed" => "0"} -> false
      _ -> conn.cookies[@cookie_name] == "1"
    end
  end

  def on_mount(:mount_sidebar_state, _params, _session, socket) do
    params = Phoenix.LiveView.get_connect_params(socket) || %{}
    sidebar_collapsed = Map.get(params, "sidebar_collapsed") == true

    {:cont,
     Phoenix.Component.assign(socket, :sidebar_collapsed, sidebar_collapsed)}
  end
end
