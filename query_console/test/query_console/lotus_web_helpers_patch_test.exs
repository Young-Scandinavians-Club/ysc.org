defmodule QueryConsole.LotusWebHelpersPatchTest do
  @moduledoc """
  `priv/lotus_web_helpers_patch.ex` is a copy of upstream
  `Lotus.Web.Helpers` with a root-mount-safe path join. When lotus_web adds a
  helper the copy has to follow, otherwise the runtime swap would drop it.
  """
  use ExUnit.Case, async: true

  @upstream Path.expand("../../deps/lotus_web/lib/lotus/web/helpers.ex", __DIR__)
  @patch Path.expand("../../priv/lotus_web_helpers_patch.ex", __DIR__)

  test "patch defines every function upstream Lotus.Web.Helpers defines" do
    missing = MapSet.difference(defs(@upstream), defs(@patch))

    assert MapSet.size(missing) == 0,
           "priv/lotus_web_helpers_patch.ex is missing: #{inspect(MapSet.to_list(missing))}"
  end

  test "patched module is active and joins root-mounted paths" do
    assert function_exported?(Lotus.Web.Helpers, :__query_console_patched__, 0)

    socket = %Phoenix.LiveView.Socket{
      endpoint: QueryConsoleWeb.Endpoint,
      router: QueryConsoleWeb.Router
    }

    Lotus.Web.Helpers.put_router_prefix(socket, "")

    assert Lotus.Web.Helpers.lotus_path("") == "/"
    assert Lotus.Web.Helpers.lotus_path("queries/new") == "/queries/new"
    assert Lotus.Web.Helpers.lotus_path(["queries", "1"]) == "/queries/1"
  end

  defp defs(path) do
    ~r/^  def (\w+[?!]?)/m
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> List.flatten()
    |> Enum.reject(&String.starts_with?(&1, "__"))
    |> MapSet.new()
  end
end
