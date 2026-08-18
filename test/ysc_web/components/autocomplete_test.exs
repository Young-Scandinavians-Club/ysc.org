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
  end
end
