defmodule YscWeb.Api.PropertiesJSON do
  @moduledoc """
  JSON rendering for property info API responses.

  Returns property info with `tabs` for React Native tab-based rendering.
  Content uses Markdown (`content_format: "markdown"`) for rich formatting.
  """

  def info(%{
        property: property,
        settings: settings,
        static_info: static_info,
        rooms: rooms,
        active_door_code: active_door_code
      }) do
    tabs = build_tabs(static_info.rules_categories, static_info.rules)
    door_code = door_code_from_active_or_settings(active_door_code, settings)

    %{
      data: %{
        property: property,
        name: static_info.name,
        content_format: "markdown",
        check_in_time:
          Map.get(settings, "check_in_time") || static_info.check_in_time,
        check_out_time:
          Map.get(settings, "check_out_time") || static_info.check_out_time,
        check_in_instructions: Map.get(settings, "check_in_instructions"),
        check_out_instructions: Map.get(settings, "check_out_instructions"),
        notices: Map.get(settings, "notices"),
        wifi_network: Map.get(settings, "wifi_network"),
        wifi_password: Map.get(settings, "wifi_password"),
        door_code: door_code,
        rooms: Enum.map(rooms, &room/1),
        tabs: tabs,
        additional_settings: settings
      }
    }
  end

  defp door_code_from_active_or_settings(%{code: code}, _settings), do: code

  defp door_code_from_active_or_settings(nil, settings),
    do: Map.get(settings, "door_code")

  defp room(r) do
    %{
      id: to_string(r.id),
      name: r.name
    }
  end

  defp build_tabs(categories, rules) do
    Enum.map(categories, fn %{id: id, title: title} ->
      sections = Map.get(rules, id, [])
      %{id: id, title: title, sections: sections}
    end)
  end
end
