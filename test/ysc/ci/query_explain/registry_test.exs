defmodule Ysc.Ci.QueryExplain.RegistryTest do
  use ExUnit.Case, async: true

  alias Ysc.Ci.QueryExplain.Registry

  test "core modules export ci_query_explain_query/0 (spot-check, no full lib scan)" do
    # Avoid Registry.all_targets/0 here — it wildcards + parses all of lib/ysc
    # (~0.5–0.7s). Full discovery is exercised by the CI query-explain task.
    for {module, function} <- [
          {Ysc.Bookings, :ci_query_explain_query},
          {Ysc.Events, :ci_query_explain_query},
          {Ysc.Events, :upcoming_events_with_preload_query}
        ] do
      assert {:module, ^module} = Code.ensure_loaded(module)
      assert function_exported?(module, function, 0)
      assert match?(%Ecto.Query{}, apply(module, function, []))
    end
  end

  test "lib_ysc_scope? is true when any lib/ysc file changed" do
    refute Registry.lib_ysc_scope?(MapSet.new(["lib/ysc_web/live/foo_live.ex"]))
    assert Registry.lib_ysc_scope?(MapSet.new(["lib/ysc/bookings.ex"]))
  end

  test "lib_ysc_paths/0 includes bookings and events sources" do
    paths = Registry.lib_ysc_paths()

    assert Enum.any?(paths, &String.ends_with?(&1, "/bookings.ex"))
    assert Enum.any?(paths, &String.ends_with?(&1, "/events.ex"))
  end
end
