defmodule YscWeb.AdminEventSearchTest do
  use Ysc.DataCase, async: true

  import Ysc.EventsFixtures

  alias YscWeb.AdminEventSearch

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end

  defp event_titled(title) do
    event_fixture(%{title: title})
  end

  describe "assign_blank/2" do
    test "clears the picker and gives it empty suggestions" do
      updated =
        AdminEventSearch.assign_blank(
          socket(%{
            selected_event: %{id: "1"},
            event_search: "Ga",
            event_search_results: [%{id: "1"}]
          })
        )

      assert updated.assigns.selected_event == nil
      assert updated.assigns.event_search == ""
      assert updated.assigns.event_search_results == []
      assert updated.assigns.event_suggestions == []
    end

    test "keeps suggestions that were already loaded" do
      updated =
        AdminEventSearch.assign_blank(
          socket(%{event_suggestions: [%{id: "1"}]})
        )

      assert updated.assigns.event_suggestions == [%{id: "1"}]
    end

    test "clears custom assign names" do
      updated =
        AdminEventSearch.assign_blank(
          socket(%{linked_event: %{id: "1"}, linked_search: "Ga"}),
          selected: :linked_event,
          search: :linked_search,
          results: :linked_results,
          suggestions: :linked_suggestions
        )

      assert updated.assigns.linked_event == nil
      assert updated.assigns.linked_search == ""
      assert updated.assigns.linked_results == []
      assert updated.assigns.linked_suggestions == []
    end
  end

  describe "assign_suggestions/2" do
    test "loads upcoming events" do
      event = event_titled("Suggested Gala")

      updated = AdminEventSearch.assign_suggestions(socket())

      assert Enum.any?(updated.assigns.event_suggestions, &(&1.id == event.id))
    end
  end

  describe "search/3" do
    test "returns matching events for queries of at least 2 characters" do
      event = event_titled("Searchable Gala")

      updated = AdminEventSearch.search(socket(), "Searchable")

      assert updated.assigns.event_search == "Searchable"

      assert Enum.any?(
               updated.assigns.event_search_results,
               &(&1.id == event.id)
             )
    end

    test "returns no results for queries shorter than 2 characters" do
      _event = event_titled("Another Gala")

      updated = AdminEventSearch.search(socket(), "A ")

      assert updated.assigns.event_search == "A "
      assert updated.assigns.event_search_results == []
    end

    test "honors custom result assign names" do
      event = event_titled("Customizable Gala")

      updated =
        AdminEventSearch.search(socket(), "Customizable",
          search: :linked_search,
          results: :linked_results
        )

      assert Enum.any?(updated.assigns.linked_results, &(&1.id == event.id))
    end
  end

  describe "select/3" do
    test "loads the event and selects it" do
      event = event_titled("Selectable Gala")

      updated =
        AdminEventSearch.select(
          socket(%{event_search: "Sel", event_search_results: [%{id: "x"}]}),
          event.id
        )

      assert updated.assigns.selected_event.id == event.id
      assert updated.assigns.selected_event.title == "Selectable Gala"
      assert updated.assigns.event_search == ""
      assert updated.assigns.event_search_results == []
    end

    test "leaves the picker blank when the event is gone" do
      gone = event_fixture(%{state: :deleted})

      updated = AdminEventSearch.select(socket(), gone.id)

      assert updated.assigns.selected_event == nil
    end
  end
end
