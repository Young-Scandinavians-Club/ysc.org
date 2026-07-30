defmodule QueryConsoleWeb.LotusPathFix do
  @moduledoc false

  def on_mount(:default, _params, _session, socket) do
    QueryConsole.LotusWeb.HelpersPatch.ensure!()
    {:cont, socket}
  end
end
