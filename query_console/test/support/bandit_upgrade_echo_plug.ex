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

  def call(%Plug.Conn{path_info: ["large"]} = conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, String.duplicate("a", 400))
  end

  def call(%Plug.Conn{path_info: ["png"]} = conn, _opts) do
    conn
    |> put_resp_content_type("image/png")
    |> send_resp(200, String.duplicate("a", 400))
  end

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "bandit-upgrade-ok")
  end
end
