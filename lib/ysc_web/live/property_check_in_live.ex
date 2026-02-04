defmodule YscWeb.PropertyCheckInLive do
  use YscWeb, :live_view
  use YscNative, :live_view

  alias Ysc.Bookings

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"last_name" => ""}, as: :search)
    vehicle_make_form = to_form(%{"make" => ""}, as: :vehicle)
    rules_form = to_form(%{"rules_agreement" => false}, as: :rules)

    {:ok,
     socket
     |> assign(:last_name, "")
     |> assign(:step, :search)
     |> assign(:form, form)
     |> assign(:search_results, [])
     |> assign(:reservation, nil)
     |> assign(:matching_guests, [])
     |> assign(:vehicles, [])
     |> assign(:vehicle_step, :overview)
     |> assign(:vehicle_draft, %{type: nil, color: nil, make: ""})
     |> assign(:vehicle_make_form, vehicle_make_form)
     |> assign(:rules_form, rules_form)
     |> assign(:rules_agreed, false)
     |> assign(:confirm_button_style, build_confirm_button_style())
     |> assign(:confirm_button_disabled, true)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    # Parse URI to get current path and send to SwiftUI
    parsed_uri = URI.parse(uri)
    current_path = parsed_uri.path || "/"

    # Send current path to SwiftUI via push_event
    socket =
      socket
      |> Phoenix.LiveView.push_event("current_path", %{path: current_path})

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "update_last_name",
        %{"search" => %{"last_name" => last_name}},
        socket
      ) do
    update_last_name(last_name, socket)
  end

  # LiveView Native LiveForm currently emits unnested params (e.g. %{"last_name" => "Doe"})
  # for both phx-change and phx-submit, so we accept both shapes.
  def handle_event("update_last_name", %{"last_name" => last_name}, socket) do
    update_last_name(last_name, socket)
  end

  def handle_event("search_reservation", %{"search" => search_params}, socket) do
    search_reservation(search_params, socket)
  end

  def handle_event("search_reservation", params, socket) when is_map(params) do
    search_reservation(params, socket)
  end

  def handle_event("select_reservation", %{"number" => reference_id}, socket) do
    try do
      # Try to find booking by reference_id first, then by id (in case it's a ULID)
      booking =
        case Bookings.get_booking_by_reference_id(reference_id) do
          nil ->
            # Fallback to ID lookup (in case the template passes ID instead of reference_id)
            try do
              Bookings.get_booking!(reference_id)
            rescue
              Ecto.NoResultsError -> nil
            end

          booking ->
            booking
        end

      if is_nil(booking) do
        {:noreply,
         put_flash(
           socket,
           :error,
           "Reservation not found. Please search again."
         )}
      else
        reservation = transform_booking_to_reservation(booking)

        {:noreply,
         socket
         |> assign(:step, :confirm)
         |> assign(:reservation, reservation)
         |> assign(:booking, booking)
         |> assign(:matching_guests, reservation.guests)
         |> assign(:vehicles, [])
         |> assign(:vehicle_step, :overview)
         |> assign(:vehicle_draft, %{type: nil, color: nil, make: ""})
         |> assign(:vehicle_make_form, to_form(%{"make" => ""}, as: :vehicle))
         |> assign(
           :rules_form,
           to_form(%{"rules_agreement" => false}, as: :rules)
         )
         |> assign(:rules_agreed, false)
         |> assign(:confirm_button_style, build_confirm_button_style())
         |> assign(:confirm_button_disabled, true)}
      end
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Reservation not found. Please search again."
         )}
    end
  end

  def handle_event("clear_reservation", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :search)
     |> assign(:reservation, nil)
     |> assign(:matching_guests, [])
     |> assign(:vehicles, [])
     |> assign(:vehicle_step, :overview)
     |> assign(:vehicle_draft, %{type: nil, color: nil, make: ""})
     |> assign(:vehicle_make_form, to_form(%{"make" => ""}, as: :vehicle))
     |> assign(:rules_form, to_form(%{"rules_agreement" => false}, as: :rules))
     |> assign(:rules_agreed, false)
     |> assign(:confirm_button_style, build_confirm_button_style())
     |> assign(:confirm_button_disabled, true)}
  end

  # Handle phx-change events from rules agreement form
  def handle_event(
        "update_rules_agreement",
        %{"rules" => %{"rules_agreement" => value}},
        socket
      ) do
    new_value = value == true or value == "true"
    confirm_button_style = build_confirm_button_style()

    {:noreply,
     socket
     |> assign(:rules_agreed, new_value)
     |> assign(
       :rules_form,
       to_form(%{"rules_agreement" => new_value}, as: :rules)
     )
     |> assign(:confirm_button_style, confirm_button_style)
     |> assign(:confirm_button_disabled, !new_value)}
  end

  def handle_event("update_rules_agreement", params, socket) do
    # Handle unnested params from LiveView Native
    value = Map.get(params, "rules_agreement", false)
    new_value = value == true or value == "true"
    confirm_button_style = build_confirm_button_style()

    {:noreply,
     socket
     |> assign(:rules_agreed, new_value)
     |> assign(
       :rules_form,
       to_form(%{"rules_agreement" => new_value}, as: :rules)
     )
     |> assign(:confirm_button_style, confirm_button_style)
     |> assign(:confirm_button_disabled, !new_value)}
  end

  def handle_event("confirm_reservation", _params, socket) do
    if socket.assigns.rules_agreed do
      {:noreply,
       socket
       |> assign(:step, :vehicles)
       |> assign(:vehicle_step, :overview)
       |> assign(:vehicle_draft, %{type: nil, color: nil, make: ""})
       |> assign(:vehicle_make_form, to_form(%{"make" => ""}, as: :vehicle))}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Please confirm that you have read and understand the booking and cabin rules."
       )}
    end
  end

  # Vehicle wizard
  def handle_event("start_add_vehicle", _params, socket) do
    {:noreply,
     socket
     |> assign(:vehicle_step, :type)
     |> assign(:vehicle_draft, %{type: nil, color: nil, make: ""})
     |> assign(:vehicle_make_form, to_form(%{"make" => ""}, as: :vehicle))}
  end

  def handle_event("select_vehicle_type", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(:vehicle_draft, %{socket.assigns.vehicle_draft | type: type})
     |> assign(:vehicle_step, :color)}
  end

  def handle_event("select_vehicle_color", %{"color" => color}, socket) do
    {:noreply,
     socket
     |> assign(:vehicle_draft, %{socket.assigns.vehicle_draft | color: color})
     |> assign(:vehicle_step, :make)}
  end

  # LiveView Native LiveForm currently emits unnested params for phx-change, so accept both shapes.
  def handle_event(
        "update_vehicle_make",
        %{"vehicle" => %{"make" => make}},
        socket
      ) do
    update_vehicle_make(make, socket)
  end

  def handle_event("update_vehicle_make", %{"make" => make}, socket) do
    update_vehicle_make(make, socket)
  end

  def handle_event("add_vehicle", %{"vehicle" => vehicle_params}, socket) do
    add_vehicle(vehicle_params, socket)
  end

  def handle_event("add_vehicle", params, socket) when is_map(params) do
    add_vehicle(params, socket)
  end

  def handle_event("remove_vehicle", %{"id" => id}, socket) do
    {id, _} = Integer.parse(to_string(id))
    vehicles = Enum.reject(socket.assigns.vehicles, fn v -> v.id == id end)
    {:noreply, assign(socket, :vehicles, vehicles)}
  end

  def handle_event("skip_cars", _params, socket) do
    booking = socket.assigns.booking
    rules_agreed = socket.assigns.rules_agreed

    if is_nil(booking) do
      {:noreply,
       put_flash(socket, :error, "No booking selected. Please search again.")}
    else
      attrs = %{
        rules_agreed: rules_agreed,
        bookings: [booking],
        vehicles: []
      }

      case Bookings.create_check_in(attrs) do
        {:ok, _check_in} ->
          {:noreply,
           socket
           |> assign(:step, :done)
           |> clear_flash()
           |> put_flash(:info, "Check-in completed successfully!")}

        {:error, _changeset} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Failed to complete check-in. Please try again."
           )}
      end
    end
  end

  def handle_event("finish_check_in", _params, socket) do
    booking = socket.assigns.booking
    vehicles = socket.assigns.vehicles
    rules_agreed = socket.assigns.rules_agreed

    if is_nil(booking) do
      {:noreply,
       put_flash(socket, :error, "No booking selected. Please search again.")}
    else
      vehicle_attrs =
        Enum.map(vehicles, fn vehicle ->
          %{
            "type" => vehicle.type,
            "color" => vehicle.color,
            "make" => vehicle.make
          }
        end)

      attrs = %{
        rules_agreed: rules_agreed,
        bookings: [booking],
        vehicles: vehicle_attrs
      }

      case Bookings.create_check_in(attrs) do
        {:ok, _check_in} ->
          {:noreply,
           socket
           |> assign(:step, :done)
           |> clear_flash()
           |> put_flash(:info, "Check-in completed successfully!")}

        {:error, _changeset} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Failed to complete check-in. Please try again."
           )}
      end
    end
  end

  def handle_event("back", _params, socket) do
    case socket.assigns.step do
      :search ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      :confirm ->
        {:noreply,
         socket
         |> assign(:step, :search)
         |> assign(:reservation, nil)
         |> assign(:matching_guests, [])
         |> assign(:vehicles, [])
         |> assign(:vehicle_step, :overview)
         |> assign(:vehicle_draft, %{type: nil, color: nil, make: ""})
         |> assign(:vehicle_make_form, to_form(%{"make" => ""}, as: :vehicle))}

      :vehicles ->
        case socket.assigns.vehicle_step do
          :overview ->
            {:noreply,
             socket
             |> assign(:step, :confirm)
             |> assign(
               :rules_form,
               to_form(%{"rules_agreement" => socket.assigns.rules_agreed},
                 as: :rules
               )
             )}

          :type ->
            {:noreply, assign(socket, :vehicle_step, :overview)}

          :color ->
            {:noreply, assign(socket, :vehicle_step, :type)}

          :make ->
            {:noreply, assign(socket, :vehicle_step, :color)}
        end

      :done ->
        {:noreply, push_navigate(socket, to: ~p"/")}
    end
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

  defp build_confirm_button_style do
    [
      "buttonStyle(.borderedProminent)",
      "controlSize(.large)",
      "frame(maxWidth: .infinity)"
    ]
  end

  defp update_vehicle_make(make, socket) do
    make =
      make
      |> to_string()
      |> String.trim()

    {:noreply,
     socket
     |> assign(:vehicle_draft, %{socket.assigns.vehicle_draft | make: make})
     |> assign(:vehicle_make_form, to_form(%{"make" => make}, as: :vehicle))}
  end

  defp add_vehicle(vehicle_params, socket) do
    make =
      vehicle_params
      |> Map.get("make", socket.assigns.vehicle_draft.make)
      |> to_string()
      |> String.trim()

    socket =
      socket
      |> assign(:vehicle_draft, %{socket.assigns.vehicle_draft | make: make})
      |> assign(:vehicle_make_form, to_form(%{"make" => make}, as: :vehicle))

    %{type: type, color: color} = socket.assigns.vehicle_draft

    cond do
      is_nil(type) or type == "" ->
        {:noreply, put_flash(socket, :error, "Please select a car type.")}

      is_nil(color) or color == "" ->
        {:noreply, put_flash(socket, :error, "Please select a car color.")}

      make == "" ->
        {:noreply,
         put_flash(socket, :error, "Please enter the maker (e.g. Subaru).")}

      true ->
        vehicle = %{
          id: System.unique_integer([:positive]),
          type: type,
          color: color,
          make: make
        }

        vehicles = socket.assigns.vehicles ++ [vehicle]

        {:noreply,
         socket
         |> clear_flash()
         |> assign(:vehicles, vehicles)
         |> assign(:vehicle_step, :overview)
         |> assign(:vehicle_draft, %{type: nil, color: nil, make: ""})
         |> assign(:vehicle_make_form, to_form(%{"make" => ""}, as: :vehicle))}
    end
  end

  defp search_reservation(search_params, socket) do
    last_name =
      search_params
      |> Map.get("last_name", socket.assigns.last_name)
      |> to_string()
      |> String.trim()
      |> String.upcase()

    socket =
      assign(socket, :form, to_form(%{"last_name" => last_name}, as: :search))

    if last_name == "" do
      {:noreply,
       socket
       |> assign(:search_results, [])
       |> assign(:step, :search)
       |> assign(:reservation, nil)
       |> assign(:matching_guests, [])
       |> put_flash(:error, "Please enter a last name.")}
    else
      bookings = Bookings.search_bookings_by_last_name(last_name, :tahoe)

      if bookings == [] do
        {:noreply,
         socket
         |> assign(:search_results, [])
         |> assign(:step, :search)
         |> assign(:reservation, nil)
         |> assign(:matching_guests, [])
         |> put_flash(:error, "No reservation found for that last name.")}
      else
        search_results = Enum.map(bookings, &transform_booking_to_reservation/1)

        {:noreply,
         socket
         |> assign(:search_results, search_results)
         |> assign(:step, :search)
         |> assign(:reservation, nil)
         |> assign(:matching_guests, [])}
      end
    end
  end

  defp update_last_name(last_name, socket) do
    last_name =
      last_name
      |> to_string()
      |> String.trim()
      |> String.upcase()

    # LiveView Native triggers phx-change right before phx-submit when tapping
    # the submit button; if the value hasn't changed, don't clear/reset UI.
    if last_name == socket.assigns.last_name do
      {:noreply,
       assign(socket, :form, to_form(%{"last_name" => last_name}, as: :search))}
    else
      {:noreply,
       socket
       |> assign(:last_name, last_name)
       |> assign(:step, :search)
       |> assign(:form, to_form(%{"last_name" => last_name}, as: :search))
       |> assign(:search_results, [])
       |> assign(:reservation, nil)
       |> assign(:matching_guests, [])}
    end
  end

  defp transform_booking_to_reservation(booking) do
    property_name = get_property_name(booking.property)

    # Get guests assigned to rooms
    booking_guests = booking.booking_guests || []

    # Map guests to expected format
    guests =
      Enum.map(booking_guests, fn guest ->
        # Find which room this guest is assigned to (if any)
        # For now, we'll use the first room if booking has rooms
        room_name =
          if booking.rooms && booking.rooms != [] do
            Enum.at(booking.rooms, 0).name
          else
            nil
          end

        %{
          id: guest.id,
          first_name: guest.first_name,
          last_name: guest.last_name,
          room: room_name || "—",
          arrived: false,
          is_primary: guest.is_booking_user || false
        }
      end)

    # Build rooms list - just room names that are part of the booking
    rooms =
      if booking.rooms && booking.rooms != [] do
        Enum.map(booking.rooms, & &1.name)
      else
        []
      end

    %{
      number: booking.reference_id,
      booking_id: booking.id,
      property_name: property_name,
      wifi_password: get_wifi_password(booking.property),
      adult_count: booking.guests_count || 1,
      child_count: booking.children_count || 0,
      checkin_date: booking.checkin_date,
      checkout_date: booking.checkout_date,
      guests: guests,
      rooms: rooms
    }
  end

  defp get_property_name(:tahoe), do: "Tahoe Cabin"
  defp get_property_name(:clear_lake), do: "Clear Lake Cabin"

  defp get_property_name(property) when is_atom(property),
    do: String.capitalize(to_string(property)) <> " Cabin"

  defp get_property_name(property), do: to_string(property) <> " Cabin"

  defp get_wifi_password(:tahoe), do: "Welcome2024!"
  defp get_wifi_password(:clear_lake), do: "ClearLake2024!"
  defp get_wifi_password(_), do: "ContactProperty"
end
