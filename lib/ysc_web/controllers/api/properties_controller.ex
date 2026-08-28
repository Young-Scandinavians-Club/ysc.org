defmodule YscWeb.Api.PropertiesController do
  @moduledoc """
  REST API controller for property information.

  Returns property rules, check-in/check-out instructions, and notices
  for a given property.
  """
  use YscWeb, :controller

  alias Ysc.Bookings
  alias Ysc.Bookings.{PropertyDisplay, SeasonCache, SeasonHelpers}
  alias Ysc.Extensions.PhoneNumber
  alias Ysc.Settings
  alias YscWeb.BookingDisplay
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
    Map.merge(property_hours(), %{
      name: PropertyDisplay.full_name(:tahoe),
      rules_categories: tahoe_rule_categories(),
      rules: tahoe_rules(cabin_master)
    })
  end

  defp static_property_info(:clear_lake, cabin_master) do
    Map.merge(property_hours(), %{
      name: PropertyDisplay.full_name(:clear_lake),
      rules_categories: clear_lake_rule_categories(),
      rules: clear_lake_rules(cabin_master)
    })
  end

  defp property_hours do
    %{
      check_in_time: BookingDisplay.checkin_time_label(),
      check_out_time: BookingDisplay.checkout_time_label()
    }
  end

  defp tahoe_rule_categories do
    [
      %{id: "welcome", title: "Arrival"},
      %{id: "etiquette", title: "House Rules"},
      %{id: "bears", title: "Bear & Wildlife"},
      %{id: "parking", title: "Parking & Driving"},
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
            "Since **1993**, this cabin has been a community effort. We keep rates low because we don't hire a cleaning crew—**you are the steward of the cabin during your stay.**\n\n**Wi-Fi:** See the network and password fields above.\n**Address:** `2685 Cedar Lane, Homewood, CA`\n**Payment:** Must be completed **in advance** on the website before your arrival."
        },
        %{
          title: "The Must-Bring List",
          content:
            "**Linens and towels are NOT provided.** You must bring:\n\n- Bedding (sheets, pillowcases, or sleeping bags)\n- Towels (for showers and the sauna)\n- Fire starters/kindling — wood is provided but may be damp\n- Food and ingredients (kitchen is fully equipped)\n\n> **No pets** — no exceptions. **No smoking or vaping** indoors or on decks.\n\n**Pro tip:** Bring an extra layer — Tahoe nights get cold even in summer."
        }
      ],
      "etiquette" => [
        %{
          title: "Quiet Hours & Respect",
          content:
            "Quiet hours are **10:00 PM – 7:00 AM.**\n\nTreat the cabin as your own — it's **not a hotel.** Stairs and hallways carry sound easily, so be considerate of other guests."
        },
        %{
          title: "Shared Spaces & Storage",
          content:
            "- Keep personal items out of shared spaces.\n- Store **ski boots** in the laundry room racks.\n- Store other gear in the **outside stairwell**."
        },
        %{
          title: "Pets, Smoking & Children",
          content:
            "**Pets:** Not allowed — no exceptions.\n**Smoking & vaping:** Prohibited indoors and on decks.\n**Children:** For safety, children should not play on or near the stairs."
        }
      ],
      "bears" => [
        %{
          title: "Bear Safety & Electric Wire",
          content:
            "The deck is surrounded by an **electric bear wire** — it won't harm you, but must be handled in order.\n\n**To enter:**\n1. Grab the **top** black handle and disconnect it.\n2. Remove the second wire.\n3. Remove the third wire, then step inside.\n\n**When leaving or going to sleep** (reverse order):\n1. Connect the **lowest** wire first.\n2. Connect the middle wire.\n3. Connect the **top** wire last to reactivate the barrier.\n\n> Always secure garbage cans and remove all food waste from outdoor areas."
        }
      ],
      "parking" => [
        %{
          title: "Parking",
          content:
            "Parking is extremely limited — **carpool if possible.**\n\n- You may need to move your vehicle to accommodate others.\n- Do not block driveways or neighbors' access.\n\n> **No street parking November 1 – May 1.** Towing is strictly enforced for snow removal and carries steep penalties."
        },
        %{
          title: "Winter Driving",
          content:
            "- Carry **snow chains** or use a **4WD vehicle with snow tires**.\n- Check road and weather conditions before traveling.\n\n**Caltrans Road Info:** `(800) 427-7623`"
        },
        %{
          title: "Local Transportation",
          content:
            "**Tahoe Bus Transit:** `(530) 581-6365`\n**Tahoe Taxi:** `(530) 546-3181`"
        }
      ],
      "checkout" => [
        %{
          title: "The Dugnad Cleaning Checklist",
          content:
            "\"Dugnad\" is our tradition of community work. Please complete these before **#{BookingDisplay.checkout_time_label()}**:\n\n- **Rooms:** Strip beds and clean the space.\n- **Laundry:** If you used club bedding, wash, dry, and fold it.\n- **Kitchen:** Wash all dishes and remove all food from the fridge.\n- **Bathrooms:** Wipe down surfaces (supplies are in sink cabinets).\n- **Trash:** Secure all bear bins and turn the bear wire **ON**.\n- **Storage:** Ski boots in laundry room racks; other gear in the outside stairwell."
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
      %{id: "etiquette", title: "House Rules"},
      %{id: "water", title: "Dock & Water Safety"},
      %{id: "parking", title: "Parking & Driving"},
      %{id: "cleaning", title: "Kitchen & Mats"},
      %{id: "checkout", title: "Locking Up"},
      %{id: "emergency", title: "Emergency"}
    ]
  end

  defp clear_lake_rules(cabin_master) do
    {summer_window, winter_window} = clear_lake_season_windows()

    %{
      "welcome" => [
        %{
          title: "Welcome to Clear Lake",
          content:
            "We hope you enjoy the pool and the lake! Please remember to sign the guest book upon arrival."
        },
        %{
          title: "What's Here",
          content:
            "- **The Private Dock** — swimming, sunbathing, boat mooring.\n- **Social Hall** — cedar hall with a wood-burning fireplace and dance floor.\n- **Group Kitchen** — industrial stoves and ample fridge space.\n- **Sleeping:** Summer (#{summer_window}): no beds — lawn camp or bring your own sleeping setup. Winter (#{winter_window}): indoor beds in three rooms — two rooms with one queen each, one room with a queen and two full-size beds (bring linens & a comforter). Each room has bedside tables, lamps, heaters, storage, rugs, and coat racks."
        },
        %{
          title: "What to Bring",
          content:
            "- Sleeping gear (summer: sleeping bag, pillow, tent if camping — beds are not set up; winter: linens for indoor beds)\n- Bath & beach towels\n- Reusable water bottle\n- Sunscreen & swimsuit"
        }
      ],
      "etiquette" => [
        %{
          title: "Quiet Hours",
          content:
            "Quiet hours start at **midnight** to keep the lake peaceful for everyone."
        },
        %{
          title: "Pets & Smoking",
          content:
            "**No pets** are allowed on the property — this protects local wildlife and keeps the environment pristine.\n**Smoking & vaping:** Prohibited indoors and on decks."
        }
      ],
      "water" => [
        %{
          title: "Boating & Dock Access",
          content:
            "Members enjoy free mooring at our private dock. Email the Cabin Master **in advance** to arrange it.\n\n> Trailers must be parked **off-site**."
        },
        %{
          title: "Quagga Mussel Inspection",
          content:
            "A **mandatory Quagga mussel boat inspection** is required before launching. Violations result in a **$1,000 fine** from Lake County."
        }
      ],
      "parking" => [
        %{
          title: "Parking",
          content:
            "Parking is limited — park parallel in the lot along the water line, as close to the next car as possible, and choose a spot based on your departure time.\n\n> **Pro tip:** Leaving early Sunday? Don't park in the back or you may find yourself blocked in.\n\nDo not block the driveway or neighbors' access."
        },
        %{
          title: "Getting Here",
          content:
            "Public transportation is very limited — **driving is essential**."
        }
      ],
      "cleaning" => [
        %{
          title: "Kitchen & Sleeping Mats",
          content:
            "- **Deep Clean:** Sanitize range top, ovens, and countertops.\n- **Dishwasher:** Must be emptied **before** you depart.\n- **Sleeping Mats:** Sanitize, wipe down, and stack neatly in the storage room next to the pool toy room."
        },
        %{
          title: "Winter Season (#{winter_window})",
          content:
            "Indoor beds are set up in three separate rooms during winter. Two rooms have one queen bed each; the third has a queen and two full-size beds. Each room has bedside tables, lamps, heaters, storage, rugs, and coat racks. Bring your own linens: sheets, pillowcases, a comforter or sleeping bag, and towels. An extra wool blanket and indoor slippers help keep you cozy in the Social Hall.\n\nIn summer (#{summer_window}), beds are not set up. Lawn camp or use the cabin with your own sleeping setup."
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

  defp clear_lake_season_windows do
    seasons = SeasonCache.get_all_for_property(:clear_lake)

    winter = Enum.find(seasons, &SeasonHelpers.winter_sleeping_season?/1)
    summer = Enum.find(seasons, &SeasonHelpers.summer_sleeping_season?/1)

    {
      SeasonHelpers.format_season_window(summer) || "May 1 – Oct 31",
      SeasonHelpers.format_season_window(winter) || "Nov 1 – Apr 30"
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
