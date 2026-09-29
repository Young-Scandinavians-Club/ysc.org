defmodule YscWeb.AdminUserSearchTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.AdminUserSearch

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  describe "assign_blank/2" do
    test "clears the default picker assigns" do
      member = user_fixture()

      updated =
        AdminUserSearch.assign_blank(
          socket(%{
            selected_user: member,
            user_search: "Jo",
            user_search_results: [member]
          })
        )

      assert updated.assigns.selected_user == nil
      assert updated.assigns.user_search == ""
      assert updated.assigns.user_search_results == []
    end

    test "clears custom assign names" do
      member = user_fixture()

      updated =
        AdminUserSearch.assign_blank(
          socket(%{
            grant_selected_user: member,
            grant_user_search: "Jo",
            grant_user_results: [member]
          }),
          search: :grant_user_search,
          results: :grant_user_results,
          selected: :grant_selected_user
        )

      assert updated.assigns.grant_selected_user == nil
      assert updated.assigns.grant_user_search == ""
      assert updated.assigns.grant_user_results == []
    end
  end

  describe "assign_selected/3" do
    test "selects a loaded user and clears the query" do
      member = user_fixture()

      updated =
        AdminUserSearch.assign_selected(
          socket(%{user_search: "Jo", user_search_results: [member]}),
          member
        )

      assert updated.assigns.selected_user.id == member.id
      assert updated.assigns.user_search == ""
      assert updated.assigns.user_search_results == []
    end
  end

  describe "search/3" do
    test "returns matching users for queries of at least 2 characters" do
      member = user_fixture(%{first_name: "Searchable", last_name: "Picker"})

      updated = AdminUserSearch.search(socket(), "Searchable")

      assert updated.assigns.user_search == "Searchable"

      assert Enum.any?(
               updated.assigns.user_search_results,
               &(&1.id == member.id)
             )
    end

    test "returns no results for queries shorter than 2 characters" do
      _member = user_fixture(%{first_name: "Ada"})

      updated = AdminUserSearch.search(socket(), "A")

      assert updated.assigns.user_search == "A"
      assert updated.assigns.user_search_results == []
    end

    test "honors custom result assign names" do
      member = user_fixture(%{first_name: "Grantable", last_name: "Member"})

      updated =
        AdminUserSearch.search(socket(), "Grantable",
          search: :grant_user_search,
          results: :grant_user_results
        )

      assert updated.assigns.grant_user_search == "Grantable"

      assert Enum.any?(
               updated.assigns.grant_user_results,
               &(&1.id == member.id)
             )
    end
  end

  describe "select/3" do
    test "loads the user and selects them" do
      member = user_fixture()

      updated =
        AdminUserSearch.select(
          socket(%{user_search: "Jo", user_search_results: [member]}),
          member.id
        )

      assert updated.assigns.selected_user.id == member.id
      assert updated.assigns.user_search == ""
      assert updated.assigns.user_search_results == []
    end
  end
end
