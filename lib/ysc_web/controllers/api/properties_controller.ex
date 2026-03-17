defmodule YscWeb.Api.PropertiesController do
  @moduledoc """
  REST API controller for property information.

  Returns property rules, check-in/check-out instructions, and notices
  for a given property.
  """
  use YscWeb, :controller

  alias Ysc.Bookings
  alias Ysc.Extensions.PhoneNumber
  alias Ysc.Settings
  alias YscWeb.Emails.OutageNotification

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
    cabin_master = OutageNotification.get_cabin_master(property_atom)

    settings = load_property_settings(property)
    static_info = static_property_info(property_atom, cabin_master)
    rooms = Bookings.list_rooms(property_atom)
    active_door_code = Bookings.get_active_door_code(property_atom)

    render(conn, :info,
      property: property_atom,
      settings: settings,
      static_info: static_info,
      rooms: rooms,
      active_door_code: active_door_code
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

  defp static_property_info(:tahoe, cabin_master) do
    %{
      name: "Lake Tahoe Cabin",
      check_in_time: "3:00 PM",
      check_out_time: "11:00 AM",
      rules_categories: tahoe_rule_categories(),
      rules: tahoe_rules(cabin_master)
    }
  end

  defp static_property_info(:clear_lake, cabin_master) do
    %{
      name: "Clear Lake Cabin",
      check_in_time: "3:00 PM",
      check_out_time: "11:00 AM",
      rules_categories: clear_lake_rule_categories(),
      rules: clear_lake_rules(cabin_master)
    }
  end

  defp tahoe_rule_categories do
    [
      %{id: "welcome", title: "Arrival"},
      %{id: "bears", title: "Bear & Wildlife"},
      %{id: "checkout", title: "Departure"},
      %{id: "emergency", title: "Emergency"}
    ]
  end

  defp tahoe_rules(cabin_master) do
    %{
      "welcome" => [
        %{
          title: "The YSC Spirit",
          content:
            "Since **1993**, this cabin has been a community effort. We keep rates low because we don't hire a cleaning crew—**you are the steward of the cabin during your stay.**\n\n**Wi-Fi:** `YSC-Tahoe` | **Pass:** `Welcome2024!`\n**Address:** `2685 Cedar Lane, Homewood, CA`\n**Payment:** Must be completed **in advance** on the website before your arrival."
        },
        %{
          title: "The Must-Bring List",
          content:
            "**Linens and towels are NOT provided.** You must bring:\n\n- Bedding (sheets, pillowcases, or sleeping bags)\n- Towels (for showers and the sauna)\n- Fire starters/kindling\n- Food and ingredients\n\n> **No pets** — no exceptions. **No smoking or vaping** indoors or on decks."
        },
        %{
          title: "Parking",
          content:
            "Parking is extremely limited. **Carpooling is strongly encouraged.**\n\n> **No street parking** allowed from November 1 through May 1."
        }
      ],
      "bears" => [
        %{
          title: "Bear Safety & Electric Wire",
          content:
            "The cabin is in bear country. **Always turn OFF the bear wire before entering/exiting.**\n\n1. **Turn OFF:** Unhook the **TOP** handle first.\n2. **Enter:** Wait 5 seconds and step inside.\n3. **Turn ON:** Re-hook wires from **BOTTOM to TOP**.\n\n> **Garbage:** Use bear-proof lids at all times to prevent a mess!"
        }
      ],
      "checkout" => [
        %{
          title: "The Dugnad Cleaning Checklist",
          content:
            "\"Dugnad\" is our tradition of community work. Please complete these before **11:00 AM**:\n\n- **Rooms:** Strip beds and clean the space.\n- **Laundry:** If you used club bedding, wash, dry, and fold it.\n- **Kitchen:** Wash all dishes and remove all food from the fridge.\n- **Bathrooms:** Wipe down surfaces (supplies are in sink cabinets).\n- **Trash:** Secure all bear bins and turn the bear wire **ON**.\n- **Storage:** Ski boots in laundry room racks; other gear in the outside stairwell."
        },
        %{
          title: "Cabin Master Note",
          content:
            "> *\"If it's broken, fix it. If it's messy, clean it. The better we take care of it, the better we will like being there.\"* Reach out to the Cabin Master if anything needs repair."
        }
      ],
      "emergency" => tahoe_emergency_sections(cabin_master)
    }
  end

  defp clear_lake_rule_categories do
    [
      %{id: "welcome", title: "Arrival"},
      %{id: "cleaning", title: "Kitchen & Mats"},
      %{id: "checkout", title: "Locking Up"},
      %{id: "emergency", title: "Emergency"}
    ]
  end

  defp clear_lake_rules(cabin_master) do
    %{
      "welcome" => [
        %{
          title: "Welcome to Clear Lake",
          content:
            "We hope you enjoy the pool and the lake! Please remember to sign the guest book upon arrival."
        }
      ],
      "cleaning" => [
        %{
          title: "Kitchen & Sleeping Mats",
          content:
            "- **Deep Clean:** Sanitize range top, ovens, and countertops.\n- **Dishwasher:** Must be emptied **before** you depart.\n- **Sleeping Mats:** Sanitize, wipe down, and stack neatly in the storage room next to the pool toy room."
        }
      ],
      "checkout" => [
        %{
          title: "Locking Up (Required)",
          content:
            "You must lock the following areas before leaving:\n\n- The Main Cabin & Pantry\n- The Pool Room\n- Men's & Women's Bathrooms\n\n> **Key Return:** Place all **4 keys** back in the lockbox on the left side of the single entry door."
        },
        %{
          title: "Final Checklist",
          content:
            "Please find the physical **CLOSING** checklist in the Cabin Master Room to properly shut down the cabin."
        }
      ],
      "emergency" => clear_lake_emergency_sections(cabin_master)
    }
  end

  defp tahoe_emergency_sections(cabin_master) do
    cabin_master_content = build_cabin_master_content(cabin_master, :tahoe)

    local_services =
      """
      **911** for life-threatening emergencies.

      **Local services (Placer County / West Shore):**
      - Placer County Sheriff (non-emergency): (530) 581-6300
      - North Tahoe Fire: (530) 583-6913
      - Tahoe Forest Hospital (Truckee): (530) 587-6011 — Emergency: (530) 582-3206
      - Poison Control: 1-800-222-1222
      """
      |> String.trim()

    sections = []

    sections =
      if cabin_master_content != "" do
        sections ++ [%{title: "Cabin Master", content: cabin_master_content}]
      else
        sections
      end

    sections ++
      [%{title: "Emergency & Local Services", content: local_services}]
  end

  defp clear_lake_emergency_sections(cabin_master) do
    cabin_master_content = build_cabin_master_content(cabin_master, :clear_lake)

    sections = []

    sections =
      if cabin_master_content != "" do
        sections ++ [%{title: "Cabin Master", content: cabin_master_content}]
      else
        sections
      end

    sections ++
      [
        %{
          title: "Emergency",
          content: "**911** for life-threatening emergencies."
        }
      ]
  end

  defp build_cabin_master_content(nil, _property), do: ""

  defp build_cabin_master_content(cabin_master, property) do
    name =
      "#{cabin_master.first_name || ""} #{cabin_master.last_name || ""}"
      |> String.trim()

    phone =
      if cabin_master.phone_number do
        PhoneNumber.format_for_display(cabin_master.phone_number) ||
          cabin_master.phone_number
      end

    email = OutageNotification.get_cabin_master_email(property)

    parts =
      []
      |> maybe_append("**#{name}**", name != "")
      |> maybe_append("Phone: #{phone}", phone)
      |> maybe_append("Email: #{email}", email)

    Enum.join(parts, "\n\n")
  end

  defp maybe_append(list, _item, val) when val == false or is_nil(val), do: list
  defp maybe_append(list, item, _), do: list ++ [item]
end
