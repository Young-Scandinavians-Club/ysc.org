defmodule YscWeb.AdminFlopHelpersTest do
  use ExUnit.Case, async: true

  alias YscWeb.AdminFlopHelpers

  describe "non_flop_params/1" do
    test "drops Flop pagination and filter keys from string-keyed params" do
      params = %{
        "tab" => "upcoming",
        "order_by" => "inserted_at",
        "order_directions" => ["desc"],
        "page" => "2",
        "page_size" => "25",
        "limit" => "50",
        "offset" => "0",
        "filters" => %{"state" => "published"}
      }

      assert AdminFlopHelpers.non_flop_params(params) == %{"tab" => "upcoming"}
    end

    test "preserves atom-keyed Flop params (URL params use string keys)" do
      params = %{
        tab: :drafts,
        page: 3,
        filters: %{state: :draft}
      }

      assert AdminFlopHelpers.non_flop_params(params) == params
    end

    test "returns empty map for non-map input" do
      assert AdminFlopHelpers.non_flop_params(nil) == %{}
      assert AdminFlopHelpers.non_flop_params("page=1") == %{}
    end
  end

  describe "title_search_query/1" do
    test "returns title filter value from meta" do
      meta = %{
        flop: %{
          filters: [
            %Flop.Filter{field: :state, op: :==, value: "published"},
            %Flop.Filter{field: :title, op: :ilike, value: "Viking"}
          ]
        }
      }

      assert AdminFlopHelpers.title_search_query(meta) == "Viking"
    end

    test "returns empty string when no title filter" do
      meta = %{
        flop: %{filters: [%Flop.Filter{field: :state, op: :==, value: "draft"}]}
      }

      assert AdminFlopHelpers.title_search_query(meta) == ""
      assert AdminFlopHelpers.title_search_query(nil) == ""
    end
  end

  describe "build_title_search_filter_params/2" do
    test "builds indexed title filter params and preserves other filters" do
      meta = %{
        flop: %{
          filters: [
            %Flop.Filter{field: :state, op: :==, value: "published"},
            %Flop.Filter{field: :title, op: :ilike, value: "old"}
          ]
        }
      }

      assert AdminFlopHelpers.build_title_search_filter_params(meta, "new") ==
               %{
                 "0" => %{
                   "field" => "title",
                   "op" => "ilike",
                   "value" => "new"
                 },
                 "1" => %{
                   "field" => "state",
                   "op" => "==",
                   "value" => "published"
                 }
               }
    end

    test "removes title filter when query is empty" do
      meta = %{
        flop: %{
          filters: [
            %Flop.Filter{field: :title, op: :ilike, value: "old"},
            %Flop.Filter{field: :state, op: :==, value: "published"}
          ]
        }
      }

      assert AdminFlopHelpers.build_title_search_filter_params(meta, "") == %{
               "0" => %{
                 "field" => "state",
                 "op" => "==",
                 "value" => "published"
               }
             }
    end

    test "handles nil meta" do
      assert AdminFlopHelpers.build_title_search_filter_params(nil, "query") ==
               %{
                 "0" => %{
                   "field" => "title",
                   "op" => "ilike",
                   "value" => "query"
                 }
               }
    end
  end

  describe "list_filter_params/3" do
    test "compacts filters, preserves title search, and merges date range" do
      meta = %{
        flop: %{
          filters: [%Flop.Filter{field: :title, op: :ilike, value: "Viking"}]
        }
      }

      params = %{
        "_target" => ["date_from"],
        "date_from" => "2026-01-01",
        "date_to" => "2026-03-31",
        "filters" => %{
          "0" => %{"field" => "status", "op" => "in", "value" => "draft"},
          "1" => %{"field" => "creator_id", "op" => "in", "value" => [""]}
        }
      }

      assert AdminFlopHelpers.list_filter_params(params, meta) == %{
               "filters" => %{
                 "0" => %{
                   "field" => "status",
                   "op" => "in",
                   "value" => "draft"
                 },
                 "1" => %{
                   "field" => "title",
                   "op" => "ilike",
                   "value" => "Viking"
                 }
               },
               "date_from" => "2026-01-01",
               "date_to" => "2026-03-31"
             }
    end

    test "merges extra keys such as tab" do
      params = %{
        "date_from" => "2026-08-01",
        "date_to" => "",
        "filters" => %{}
      }

      assert AdminFlopHelpers.list_filter_params(params, nil, %{
               "tab" => "upcoming"
             }) == %{
               "filters" => %{},
               "tab" => "upcoming",
               "date_from" => "2026-08-01"
             }
    end

    test "drops LiveView internals and empty date keys" do
      params = %{
        "_target" => ["filters", "0", "value"],
        "date_from" => "",
        "date_to" => "",
        "filters" => %{
          "0" => %{"field" => "state", "op" => "in", "value" => ""}
        }
      }

      assert AdminFlopHelpers.list_filter_params(params, nil) == %{
               "filters" => %{}
             }
    end
  end

  describe "merge_date_range_into_params/3" do
    test "adds non-empty date range keys" do
      assert AdminFlopHelpers.merge_date_range_into_params(
               %{"tab" => "all"},
               "2026-01-01",
               ""
             ) ==
               %{"tab" => "all", "date_from" => "2026-01-01"}

      assert AdminFlopHelpers.merge_date_range_into_params(
               %{},
               "",
               "2026-12-31"
             ) == %{
               "date_to" => "2026-12-31"
             }
    end

    test "skips empty date range keys" do
      assert AdminFlopHelpers.merge_date_range_into_params(
               %{"tab" => "all"},
               "",
               ""
             ) == %{
               "tab" => "all"
             }
    end
  end

  describe "compact_filter_params/1" do
    test "drops empty values and normalizes multi-select blanks" do
      assert AdminFlopHelpers.compact_filter_params(%{
               "0" => %{
                 "field" => "state",
                 "op" => "==",
                 "value" => "published"
               },
               "1" => %{"field" => "author", "op" => "==", "value" => ""},
               "2" => %{"field" => "tag", "op" => "==", "value" => [""]}
             }) == %{
               "0" => %{
                 "field" => "state",
                 "op" => "==",
                 "value" => "published"
               }
             }
    end

    test "returns empty map for nil" do
      assert AdminFlopHelpers.compact_filter_params(nil) == %{}
    end
  end

  describe "merge_title_filter_into_params/2" do
    test "re-applies active title filter from meta" do
      meta = %{
        flop: %{
          filters: [%Flop.Filter{field: :title, op: :ilike, value: "keep"}]
        }
      }

      assert AdminFlopHelpers.merge_title_filter_into_params(
               %{"0" => %{"field" => "state"}},
               meta
             ) ==
               %{
                 "0" => %{"field" => "state"},
                 "1" => %{
                   "field" => "title",
                   "op" => "ilike",
                   "value" => "keep"
                 }
               }
    end

    test "leaves params unchanged when title filter is absent or empty" do
      updated = %{"0" => %{"field" => "state"}}

      assert AdminFlopHelpers.merge_title_filter_into_params(updated, nil) ==
               updated

      meta = %{
        flop: %{filters: [%Flop.Filter{field: :title, op: :ilike, value: ""}]}
      }

      assert AdminFlopHelpers.merge_title_filter_into_params(updated, meta) ==
               updated
    end
  end
end
