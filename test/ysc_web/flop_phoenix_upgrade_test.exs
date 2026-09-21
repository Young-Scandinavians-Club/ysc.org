defmodule YscWeb.FlopPhoenixUpgradeTest do
  @moduledoc """
  Guards flop_phoenix 0.27.0 (requires flop 0.29) against the pagination and
  path helpers our admin tables use. 0.27.0 resolves sortable/filterable
  fields with `Flop.allowed_fields/2`.
  """
  use ExUnit.Case, async: true

  alias Ysc.Accounts.User
  alias Ysc.Media.Image

  describe "0.27.0 lock" do
    test "locks the Hex package to 0.27.0" do
      assert to_string(Application.spec(:flop_phoenix, :vsn)) == "0.27.0"
    end

    test "table, pagination, and path helpers we use still exist" do
      assert function_exported?(Flop.Phoenix, :table, 1)
      assert function_exported?(Flop.Phoenix, :pagination, 1)
      assert function_exported?(Flop.Phoenix, :filter_fields, 1)
      assert function_exported?(Flop.Phoenix, :page_link_range, 3)
      assert function_exported?(Flop.Phoenix, :build_path, 2)
      assert function_exported?(Flop.Phoenix, :build_path, 3)
    end
  end

  describe "allowed_fields/2 used by flop_phoenix 0.27" do
    test "admin user filter fields stay filterable" do
      assert :state in Flop.allowed_fields(:filterable, for: User)
      assert :role in Flop.allowed_fields(:filterable, for: User)
      assert :membership_type in Flop.allowed_fields(:filterable, for: User)
    end

    test "admin user table sort fields stay sortable" do
      sortable = Flop.allowed_fields(:sortable, for: User)

      for field <- [:first_name, :state, :membership_type, :application_date] do
        assert field in sortable
      end
    end

    test "applies a narrowed filterable list from query options" do
      assert Flop.allowed_fields(:filterable, for: Image, filterable: [:title]) ==
               [:title]
    end
  end

  describe "page_link_range/3" do
    test "returns a window around the current page" do
      assert Flop.Phoenix.page_link_range(5, 2, 10) == {1, 5}
      assert Flop.Phoenix.page_link_range(:all, 2, 4) == {1, 4}
      assert Flop.Phoenix.page_link_range(:none, 2, 4) == {nil, nil}
    end

    test "raises ArgumentError for an invalid page-link option" do
      assert_raise ArgumentError, ~r/Invalid page link option/, fn ->
        Flop.Phoenix.page_link_range(:sometimes, 1, 3)
      end
    end
  end

  describe "build_path/3" do
    test "replaces existing Flop params on a URL string instead of appending" do
      path =
        Flop.Phoenix.build_path("/admin/users?page=1&tab=members", %Flop{
          page: 2,
          page_size: 10
        })

      uri = URI.parse(path)
      query = URI.decode_query(uri.query)

      assert uri.path == "/admin/users"
      assert query["page"] == "2"
      assert query["page_size"] == "10"
      assert query["tab"] == "members"
    end
  end
end
