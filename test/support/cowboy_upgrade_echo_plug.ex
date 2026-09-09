defmodule Ysc.CowboyUpgradeEchoPlug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "cowboy-upgrade-ok")
  end
end
