defmodule QueryConsole.BanditUpgradeEchoPlug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    case read_body(conn) do
      {:ok, body, conn} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, body)

      {:more, _chunk, conn} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(413, "too large")

      {:error, _reason} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, "read error")
    end
  end

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "bandit-upgrade-ok")
  end
end
