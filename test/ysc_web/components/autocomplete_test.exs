defmodule YscWeb.Components.AutocompleteTest do
  use YscWeb.ConnCase, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import YscWeb.Components.Autocomplete

  describe "autocomplete/1" do
    test "renders the search field when nothing is selected" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.autocomplete
          id="user-autocomplete"
          label="User"
          name="booking[user_id]"
          search_event="search-users"
          select_event="select-user"
          clear_event="clear-user"
          display_fn={fn user -> "#{user.first_name} #{user.last_name}" end}
        />
        """)

      assert html =~ ~s(id="user-autocomplete")
      assert html =~ ~s(id="user-autocomplete-input")
      assert html =~ "User"
      assert html =~ ~s(name="booking[user_id]")
      refute html =~ "phx-target"
    end

    test "renders the selected item and omits the search field" do
      assigns = %{
        selected: %{id: "user-1", first_name: "Ada", last_name: "Lovelace"}
      }

      html =
        rendered_to_string(~H"""
        <.autocomplete
          id="user-autocomplete"
          name="booking[user_id]"
          search_event="search-users"
          select_event="select-user"
          clear_event="clear-user"
          selected={@selected}
          display_fn={fn user -> "#{user.first_name} #{user.last_name}" end}
        />
        """)

      assert html =~ "Ada Lovelace"
      assert html =~ ~s(value="user-1")
      refute html =~ "user-autocomplete-input"
    end

    test "includes phx-target on interactive elements when target is set" do
      assigns = %{
        results: [%{id: "user-2", first_name: "Grace", last_name: "Hopper"}]
      }

      html =
        rendered_to_string(~H"""
        <.autocomplete
          id="user-autocomplete"
          name="booking[user_id]"
          search_event="search-users"
          select_event="select-user"
          clear_event="clear-user"
          search_value="Gr"
          results={@results}
          target="ticket-grant-form"
          display_fn={fn user -> "#{user.first_name} #{user.last_name}" end}
        />
        """)

      assert html =~ ~s(phx-target="ticket-grant-form")
      assert html =~ ~s(phx-keyup="search-users")
      assert html =~ ~s(phx-click="select-user")
      assert html =~ ~s(phx-click="clear-user")
      assert html =~ "Grace Hopper"
    end

    test "renders translated error messages" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.autocomplete
          id="user-autocomplete"
          name="booking[user_id]"
          search_event="search-users"
          select_event="select-user"
          clear_event="clear-user"
          errors={["Select a member"]}
          display_fn={fn user -> "#{user.first_name} #{user.last_name}" end}
        />
        """)

      assert html =~ "Select a member"
    end

    test "offers suggestions under a label while the query is empty" do
      assigns = %{
        suggestions: [
          %{id: "a", first_name: "Ada", last_name: "Lovelace"},
          %{id: "b", first_name: "Grace", last_name: "Hopper"}
        ]
      }

      html =
        rendered_to_string(~H"""
        <.autocomplete
          id="user-autocomplete"
          name="booking[user_id]"
          search_event="search-users"
          select_event="select-user"
          clear_event="clear-user"
          suggestions={@suggestions}
          suggestions_label="Frequent"
          display_fn={fn user -> "#{user.first_name} #{user.last_name}" end}
        />
        """)

      assert html =~ ~s(id="user-autocomplete-suggestions")
      assert html =~ "Frequent"
      assert html =~ "Ada Lovelace"
      assert html =~ ~s(phx-value-id="b")
      # Only visible while the field has focus.
      assert html =~ "group-focus-within/autocomplete:visible"
    end

    test "groups suggestions under the heading each item maps to" do
      assigns = %{
        suggestions: [
          %{
            id: "a",
            first_name: "Ada",
            last_name: "Lovelace",
            kind: "Upcoming"
          },
          %{
            id: "b",
            first_name: "Grace",
            last_name: "Hopper",
            kind: "Upcoming"
          },
          %{id: "c", first_name: "Alan", last_name: "Turing", kind: "Recent"}
        ]
      }

      html =
        rendered_to_string(~H"""
        <.autocomplete
          id="user-autocomplete"
          name="booking[user_id]"
          search_event="search-users"
          select_event="select-user"
          clear_event="clear-user"
          suggestions={@suggestions}
          suggestion_group_fn={& &1.kind}
          display_fn={fn user -> user.first_name end}
        />
        """)

      assert length(String.split(html, "Upcoming")) == 2
      assert length(String.split(html, "Recent")) == 2
      assert html =~ ~r/Upcoming.*Ada.*Grace.*Recent.*Alan/s
    end

    test "hides suggestions once there is a query or a selection" do
      assigns = %{suggestions: [%{id: "a", name: "Ada"}]}

      typing =
        rendered_to_string(~H"""
        <.autocomplete
          id="user-autocomplete"
          name="booking[user_id]"
          search_event="search-users"
          select_event="select-user"
          clear_event="clear-user"
          search_value="Ad"
          suggestions={@suggestions}
          display_fn={& &1.name}
        />
        """)

      selected =
        rendered_to_string(~H"""
        <.autocomplete
          id="user-autocomplete"
          name="booking[user_id]"
          search_event="search-users"
          select_event="select-user"
          clear_event="clear-user"
          selected={%{id: "a", name: "Ada"}}
          suggestions={@suggestions}
          display_fn={& &1.name}
        />
        """)

      refute typing =~ "user-autocomplete-suggestions"
      refute selected =~ "user-autocomplete-suggestions"
    end
  end
end
