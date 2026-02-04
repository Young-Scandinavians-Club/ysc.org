defmodule YscWeb.TahoeCabinRulesLive do
  use YscWeb, :live_view
  use YscNative, :live_view

  @impl true
  def mount(_params, _session, socket) do
    categories = get_categories()
    rules_data = get_rules_data()
    selected_category = List.first(categories)[:id]

    rules_json = Jason.encode!(%{categories: categories, rules: rules_data})

    socket =
      socket
      |> assign(:selected_category, selected_category)
      |> assign(:rules_json, rules_json)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    # Parse URI to get current path and send to SwiftUI
    parsed_uri = URI.parse(uri)
    current_path = parsed_uri.path || "/"

    # Send current path to SwiftUI via push_event
    socket =
      socket
      |> Phoenix.LiveView.push_event("current_path", %{path: current_path})

    category = Map.get(params, "category", socket.assigns.selected_category)
    {:noreply, assign(socket, :selected_category, category)}
  end

  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:selected_category, category)
     |> push_patch(to: ~p"/cabin-rules?category=#{category}")}
  end

  @impl true
  def handle_event("native_nav", %{"to" => to}, socket) do
    allowed =
      MapSet.new([
        "/",
        "/property-check-in",
        "/bookings/tahoe",
        "/bookings/tahoe/staying-with",
        "/bookings/clear-lake",
        "/cabin-rules"
      ])

    if MapSet.member?(allowed, to) do
      # Send push_event to notify SwiftUI of navigation
      socket =
        if to != "/" do
          socket
          |> Phoenix.LiveView.push_event("navigate_away_from_home", %{})
        else
          socket
          |> Phoenix.LiveView.push_event("navigate_to_home", %{})
        end

      {:noreply, push_navigate(socket, to: to)}
    else
      {:noreply, socket}
    end
  end

  defp get_categories do
    [
      %{id: "welcome", title: "Welcome", icon: "house.fill"},
      %{id: "trash", title: "Trash & Recycling", icon: "trash.fill"},
      %{id: "kitchen", title: "Kitchen & Cooking", icon: "fork.knife"},
      %{id: "bears", title: "Bear & Wildlife", icon: "pawprint.fill"},
      %{id: "quiet", title: "Quiet Hours", icon: "moon.fill"},
      %{id: "heating", title: "Heating & Logs", icon: "flame.fill"},
      %{id: "checkout", title: "Check-out", icon: "checkmark.circle.fill"},
      %{id: "emergency", title: "Emergency", icon: "phone.fill"}
    ]
  end

  defp get_rules_data do
    %{
      "welcome" => get_welcome_rules(),
      "trash" => get_trash_rules(),
      "kitchen" => get_kitchen_rules(),
      "bears" => get_bear_rules(),
      "quiet" => get_quiet_hours_rules(),
      "heating" => get_heating_rules(),
      "checkout" => get_checkout_rules(),
      "emergency" => get_emergency_rules()
    }
  end

  defp get_welcome_rules do
    [
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
          "Payment for the member and all guests must be completed in advance on the website before your arrival date. You cannot show up at the cabin without payment."
      },
      %{
        title: "What to Bring",
        content:
          "⚠️ CRITICAL: Linens and towels are NOT provided. You must bring your own bedding, sheets, pillowcases, towels, and sleeping bags. Bring your own food - the kitchen is fully equipped with appliances and spices, but you must provide all ingredients."
      },
      %{
        title: "Parking",
        content:
          "Parking is extremely limited. Carpooling is strongly encouraged. No street parking allowed from November 1 through May 1. During check-in, you'll be asked to provide vehicle information to help coordinate parking."
      }
    ]
  end

  defp get_trash_rules do
    [
      %{
        title: "TL;DR",
        content:
          "All trash must be in bear-proof bins with lids secured. Remove all food before checkout."
      },
      %{
        title: "Bear-Proof Garbage",
        content:
          "Use bear-proof lids on all garbage cans at all times. Secure bear-proof garbage lids before leaving. Bears are attracted to food smells, so proper trash management is critical for safety."
      },
      %{
        title: "Disposal",
        content:
          "Properly dispose of all trash before checkout. Remove all food from the refrigerator. All trash must be in the metal bins with lids secured."
      }
    ]
  end

  defp get_kitchen_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Fully equipped kitchen with spices. Bring your own food. Leave spotless before checkout."
      },
      %{
        title: "Kitchen Equipment",
        content:
          "The kitchen is fully equipped with all necessary appliances and cookware. Spices are available for your use."
      },
      %{
        title: "Food Storage",
        content:
          "Bring your own food. All ingredients must be provided by you. Remove all food from the refrigerator before checkout."
      },
      %{
        title: "Cleaning Requirements",
        content:
          "Leave the kitchen spotless before checkout. This includes washing all dishes, cleaning countertops, and removing all food items."
      },
      %{
        title: "Shared Fridge Space",
        content:
          "Be considerate of other guests when using the refrigerator. Label your food items and remove them before checkout."
      }
    ]
  end

  defp get_bear_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Electric bear wire protects the cabin. Always turn OFF before entering/exiting. Wait 5 seconds after turning off."
      },
      %{
        title: "Bear Safety & The Electric Wire",
        content:
          "The cabin is protected by an electric bear wire. It is safe if handled correctly, but can deliver a shock if touched while active."
      },
      %{
        title: "Entering the Cabin",
        content:
          "To enter safely: 1) Locate the switch box near the entrance, 2) Turn OFF the bear wire, 3) Wait 5 seconds, 4) Enter the property, 5) Turn the wire back ON after entering."
      },
      %{
        title: "Leaving the Cabin",
        content:
          "When leaving: 1) Turn OFF the bear wire at the switch box, 2) Wait 5 seconds, 3) Exit the property, 4) Turn the wire back ON after exiting."
      },
      %{
        title: "Important Reminders",
        content:
          "Never touch the wire when it's ON. Always turn it OFF before entering or exiting. The wire protects the cabin from bears - keep it active when not entering/exiting."
      },
      %{
        title: "Trash and Bears",
        content:
          "Use bear-proof lids on all garbage cans at all times. Bears are attracted to food smells, so proper trash management is critical for safety."
      }
    ]
  end

  defp get_quiet_hours_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Quiet hours: 10:00 PM to 7:00 AM. Stairs and hallways carry sound easily - step lightly."
      },
      %{
        title: "Quiet Hours",
        content:
          "Respect quiet hours from 10:00 PM to 7:00 AM. Please step lightly on the stairs, as they carry sound easily."
      },
      %{
        title: "General Guidelines",
        content:
          "Treat the cabin as your own — it's not a hotel. Be considerate of other guests and respect shared spaces."
      },
      %{
        title: "Common Areas & Storage",
        content:
          "Keep personal items out of shared spaces. Store ski boots in the laundry room racks. Store other gear in the outside stairwell. Do not clutter common areas."
      },
      %{
        title: "Consideration",
        content:
          "Be considerate — stairs and hallways carry sound easily. Keep noise levels down, especially during quiet hours."
      },
      %{
        title: "Children",
        content:
          "For safety and noise, children are not permitted to play on or near the stairs. Please supervise children at all times to ensure they respect quiet hours."
      }
    ]
  end

  defp get_heating_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Wood is provided but may be damp. Bring fire starter/kindling and some dry wood to start the stove."
      },
      %{
        title: "Fire-Starting",
        content:
          "Bring fire starter/kindling and some dry wood to start the stove. Wood is provided but may be damp."
      },
      %{
        title: "Heating System",
        content:
          "The cabin has a wood stove for heating. Make sure the fire is completely extinguished before leaving. Never leave a fire unattended."
      }
    ]
  end

  defp get_checkout_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Checkout is at 11:00 AM. Complete all cleaning tasks before leaving."
      },
      %{
        title: "Checkout Time",
        content:
          "Checkout is at 11:00 AM. Please ensure you have completed all required cleaning before this time."
      },
      %{
        title: "Checklist",
        content:
          "□ Strip the beds and clean your room\n□ Wash, dry, and fold any used club bedding\n□ Leave the kitchen spotless (wash all dishes, clean countertops)\n□ Remove all food from the refrigerator\n□ Secure bear-proof garbage lids\n□ Turn off all lights\n□ Ensure fire is completely extinguished (if used)\n□ Turn bear wire back ON if you turned it off"
      },
      %{
        title: "Why It Matters",
        content:
          "Keeping the cabin affordable depends on everyone pitching in! Your cooperation helps keep cabin rates low for all members."
      }
    ]
  end

  defp get_emergency_rules do
    [
      %{
        title: "TL;DR",
        content:
          "For emergencies, contact the club manager. No pets allowed. No smoking indoors."
      },
      %{
        title: "Club Manager",
        content:
          "For urgent issues, contact the club manager through the website or app."
      },
      %{
        title: "No Pets Policy",
        content:
          "No pets are allowed — no exceptions. This policy is strictly enforced."
      },
      %{
        title: "No Smoking or Vaping",
        content:
          "Smoking and vaping are prohibited indoors and on outdoor decks. This policy is strictly enforced."
      },
      %{
        title: "Local Services",
        content:
          "Emergency services: 911\nFor non-emergency issues, contact the club manager through the website."
      }
    ]
  end
end
