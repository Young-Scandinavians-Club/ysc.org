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
end
