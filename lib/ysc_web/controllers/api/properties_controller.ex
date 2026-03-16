defmodule YscWeb.Api.PropertiesController do
  @moduledoc """
  REST API controller for property information.

  Returns property rules, check-in/check-out instructions, and notices
  for a given property.
  """
  use YscWeb, :controller

  alias Ysc.Settings

  action_fallback YscWeb.Api.FallbackController

  @valid_properties ~w(tahoe clear_lake)

  @doc """
  Returns property information including rules, check-in/check-out instructions,
  and any active notices from site settings.

  Path params:
    - property: "tahoe" or "clear_lake"
  """
  def info(conn, %{"property" => property})
      when property in @valid_properties do
    property_atom = String.to_existing_atom(property)

    settings = load_property_settings(property)
    static_info = static_property_info(property_atom)

    render(conn, :info,
      property: property_atom,
      settings: settings,
      static_info: static_info
    )
  end

  def info(conn, %{"property" => _invalid}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid property. Use 'tahoe' or 'clear_lake'"})
  end

  defp load_property_settings(property) do
    prefix = "#{property}_"

    Settings.settings()
    |> Enum.filter(fn setting ->
      String.starts_with?(setting.name, prefix)
    end)
    |> Enum.map(fn setting ->
      key = String.replace_prefix(setting.name, prefix, "")
      {key, setting.value}
    end)
    |> Map.new()
  end

  defp static_property_info(:tahoe) do
    %{
      name: "Lake Tahoe Cabin",
      check_in_time: "3:00 PM",
      check_out_time: "11:00 AM",
      rules_categories: tahoe_rule_categories(),
      rules: tahoe_rules()
    }
  end

  defp static_property_info(:clear_lake) do
    %{
      name: "Clear Lake Cabin",
      check_in_time: "3:00 PM",
      check_out_time: "11:00 AM",
      rules_categories: [],
      rules: %{}
    }
  end

  defp tahoe_rule_categories do
    [
      %{id: "welcome", title: "Welcome"},
      %{id: "trash", title: "Trash & Recycling"},
      %{id: "kitchen", title: "Kitchen & Cooking"},
      %{id: "bears", title: "Bear & Wildlife"},
      %{id: "quiet", title: "Quiet Hours"},
      %{id: "heating", title: "Heating & Logs"},
      %{id: "checkout", title: "Check-out"},
      %{id: "emergency", title: "Emergency"}
    ]
  end

  defp tahoe_rules do
    %{
      "welcome" => [
        %{
          title: "TL;DR",
          content:
            "Wi-Fi: Welcome2024! | Payment required before arrival | Bring your own linens & towels"
        },
        %{
          title: "Wi-Fi Password",
          content: "Network: YSC-Tahoe | Password: Welcome2024!"
        },
        %{
          title: "Payment Required",
          content:
            "Payment for the member and all guests must be completed in advance on the website before your arrival date."
        },
        %{
          title: "What to Bring",
          content:
            "CRITICAL: Linens and towels are NOT provided. You must bring your own bedding, sheets, pillowcases, towels, and sleeping bags."
        },
        %{
          title: "Parking",
          content:
            "Parking is extremely limited. Carpooling is strongly encouraged. No street parking allowed from November 1 through May 1."
        }
      ],
      "trash" => [
        %{
          title: "TL;DR",
          content: "All trash must be in bear-proof bins with lids secured."
        },
        %{
          title: "Bear-Proof Garbage",
          content: "Use bear-proof lids on all garbage cans at all times."
        },
        %{
          title: "Disposal",
          content:
            "Properly dispose of all trash before checkout. Remove all food from the refrigerator."
        }
      ],
      "kitchen" => [
        %{
          title: "TL;DR",
          content:
            "Fully equipped kitchen with spices. Bring your own food. Leave spotless."
        },
        %{
          title: "Kitchen Equipment",
          content:
            "The kitchen is fully equipped with all necessary appliances and cookware."
        },
        %{
          title: "Cleaning Requirements",
          content:
            "Leave the kitchen spotless before checkout. Wash all dishes, clean countertops, and remove all food items."
        }
      ],
      "bears" => [
        %{
          title: "TL;DR",
          content:
            "Electric bear wire protects the cabin. Always turn OFF before entering/exiting. Wait 5 seconds."
        },
        %{
          title: "Bear Safety & The Electric Wire",
          content:
            "The cabin is protected by an electric bear wire. Turn OFF before entering or exiting."
        },
        %{
          title: "Entering the Cabin",
          content:
            "To enter safely: 1) Turn OFF the bear wire, 2) Wait 5 seconds, 3) Enter, 4) Turn back ON."
        }
      ],
      "quiet" => [
        %{
          title: "TL;DR",
          content: "Quiet hours: 10:00 PM to 7:00 AM."
        },
        %{
          title: "Quiet Hours",
          content: "Respect quiet hours from 10:00 PM to 7:00 AM."
        }
      ],
      "heating" => [
        %{
          title: "TL;DR",
          content:
            "Wood is provided but may be damp. Bring fire starter/kindling and some dry wood."
        },
        %{
          title: "Heating System",
          content:
            "The cabin has a wood stove for heating. Ensure the fire is completely extinguished before leaving."
        }
      ],
      "checkout" => [
        %{
          title: "TL;DR",
          content:
            "Checkout is at 11:00 AM. Complete all cleaning tasks before leaving."
        },
        %{
          title: "Checklist",
          content:
            "Strip the beds, wash used linens, leave kitchen spotless, remove all food, secure bear bins, turn off lights, extinguish fire, turn bear wire back ON."
        }
      ],
      "emergency" => [
        %{
          title: "TL;DR",
          content:
            "For emergencies, contact the club manager. No pets. No smoking indoors. Emergency: 911."
        },
        %{
          title: "No Pets Policy",
          content: "No pets are allowed — no exceptions."
        },
        %{
          title: "No Smoking or Vaping",
          content:
            "Smoking and vaping are prohibited indoors and on outdoor decks."
        }
      ]
    }
  end
end
