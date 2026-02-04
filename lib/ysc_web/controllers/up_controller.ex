defmodule YscWeb.UpController do
  use YscWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:ok, "")
  end

  def databases(conn, _params) do
    Ecto.Adapters.SQL.query!(Ysc.Repo, "SELECT 1")

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:ok, "")
  end
end
