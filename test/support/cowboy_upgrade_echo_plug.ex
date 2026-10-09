defmodule Ysc.CowboyUpgradeEchoPlug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.request_path do
      "/cookie" ->
        conn
        |> put_resp_cookie("upgrade", "ok",
          max_age: 60,
          same_site: "Lax",
          http_only: true
        )
        |> send_resp(200, "cookie-ok")

      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, "cowboy-upgrade-ok")
    end
  end
end
