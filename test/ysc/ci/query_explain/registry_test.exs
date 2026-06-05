defmodule Ysc.Ci.QueryExplain.RegistryTest do
  use ExUnit.Case, async: true

  alias Ysc.Ci.QueryExplain.Registry

  test "all_targets includes lib/ysc ci_query_explain_query functions" do
    targets = Registry.all_targets()
    ids = MapSet.new(targets, & &1.id)

    assert MapSet.size(ids) >= 50
    assert "ysc_bookings_ci_query_explain_query" in ids
    assert "ysc_events_ci_query_explain_query" in ids
    assert "ysc_events_upcoming_events_with_preload_query" in ids
  end

  test "lib_ysc_scope? is true when any lib/ysc file changed" do
    refute Registry.lib_ysc_scope?(MapSet.new(["lib/ysc_web/live/foo_live.ex"]))
    assert Registry.lib_ysc_scope?(MapSet.new(["lib/ysc/bookings.ex"]))
  end
end
