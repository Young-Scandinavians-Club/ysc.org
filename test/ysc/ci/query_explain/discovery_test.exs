defmodule Ysc.Ci.QueryExplain.DiscoveryTest do
  use ExUnit.Case, async: true

  alias Ysc.Ci.QueryExplain.Discovery

  describe "discoverable_query_name?/1" do
    test "accepts *_query suffix and base_query" do
      assert Discovery.discoverable_query_name?(:list_users_query)
      assert Discovery.discoverable_query_name?(:base_query)
      refute Discovery.discoverable_query_name?(:list_users)
      refute Discovery.discoverable_query_name?(:build_query)
    end
  end

  describe "query_functions_for_module/1" do
    test "discovers default-arg *_query functions" do
      assert :upcoming_events_with_preload_query in Discovery.query_functions_for_module(
               Ysc.Events
             )
    end

    test "discovers base_query/0" do
      assert :base_query in Discovery.query_functions_for_module(
               Ysc.PropertyOutages.Queries
             )
    end

    test "discovers zero-arity *_query functions" do
      assert :suspicious_events_query in Discovery.query_functions_for_module(
               Ysc.Accounts.AuthEvent
             )
    end

    test "skips functions that require arguments without defaults" do
      refute :verify_session_token_query in Discovery.query_functions_for_module(
               Ysc.Accounts.UserToken
             )
    end
  end

  describe "auto_targets_for_file/1" do
    test "builds targets for a changed context file" do
      targets =
        Discovery.auto_targets_for_file("lib/ysc/accounts/auth_event.ex")

      ids = Enum.map(targets, & &1.id)
      assert "auto_ysc_accounts_auth_event_suspicious_events_query" in ids
    end
  end

  describe "file_has_query_shape?/1" do
    test "detects Ecto query patterns" do
      assert Discovery.file_has_query_shape?("lib/ysc/events.ex")
      refute Discovery.file_has_query_shape?("lib/ysc/logging.ex")
    end
  end
end
