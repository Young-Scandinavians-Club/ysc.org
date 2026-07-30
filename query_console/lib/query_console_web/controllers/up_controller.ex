defmodule QueryConsoleWeb.UpController do
  @moduledoc false
  use QueryConsoleWeb, :controller

  def index(conn, _params) do
    text(conn, "ok")
  end
end
