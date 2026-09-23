defmodule QueryConsole.BanditUpgradeEchoPlug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "bandit-upgrade-ok")
  end
end
