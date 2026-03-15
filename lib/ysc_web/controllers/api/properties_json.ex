defmodule YscWeb.Api.PropertiesJSON do
  @moduledoc """
  JSON rendering for property info API responses.
  """

  def info(%{property: property, settings: settings, static_info: static_info}) do
    %{
      data: %{
        property: property,
        name: static_info.name,
        check_in_time:
          Map.get(settings, "check_in_time", static_info.check_in_time),
        check_out_time:
          Map.get(settings, "check_out_time", static_info.check_out_time),
        check_in_instructions: Map.get(settings, "check_in_instructions"),
        check_out_instructions: Map.get(settings, "check_out_instructions"),
        notices: Map.get(settings, "notices"),
        wifi_network: Map.get(settings, "wifi_network"),
        wifi_password: Map.get(settings, "wifi_password"),
        door_code: Map.get(settings, "door_code"),
        rules_categories: static_info.rules_categories,
        rules: static_info.rules,
        additional_settings: settings
      }
    }
  end
end
