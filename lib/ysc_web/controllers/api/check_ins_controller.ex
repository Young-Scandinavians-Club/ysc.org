defmodule YscWeb.Api.CheckInsController do
  @moduledoc """
  REST API controller for performing property check-in.

  Mirrors the check-in logic from PropertyCheckInLive, accepting the same
  data via JSON request body.
  """
  use YscWeb, :controller

  alias Ysc.Bookings

  action_fallback YscWeb.Api.FallbackController

  @doc """
  Perform check-in for one or more bookings.

  Request body (JSON):
    - property: "tahoe" or "clear_lake" (required)
    - booking_ids: list of booking IDs or reference IDs (required)
    - rules_agreed: boolean (required, must be true)
    - vehicles: list of vehicle objects (optional)
      Each vehicle: { "type": "...", "color": "...", "make": "..." }

  Example:
    {
      "property": "tahoe",
      "booking_ids": ["BK-ABC123"],
      "rules_agreed": true,
      "vehicles": [
        { "type": "sedan", "color": "blue", "make": "Toyota" }
      ]
    }
  """
  def create(conn, params) do
    with {:ok, property} <- extract_property(params),
         {:ok, booking_ids} <- extract_booking_ids(params),
         {:ok, rules_agreed} <- extract_rules_agreed(params),
         {:ok, bookings} <- resolve_bookings(booking_ids, property),
         vehicles = extract_vehicles(params),
         attrs = %{
           rules_agreed: rules_agreed,
           bookings: bookings,
           vehicles: vehicles
         },
         {:ok, check_in} <- Bookings.create_check_in(attrs) do
      conn
      |> put_status(:created)
      |> render(:show, check_in: check_in)
    end
  end

  defp extract_property(%{"property" => "tahoe"}), do: {:ok, :tahoe}
  defp extract_property(%{"property" => "clear_lake"}), do: {:ok, :clear_lake}

  defp extract_property(%{"property" => _}) do
    {:error, "invalid property. Use 'tahoe' or 'clear_lake'"}
  end

  defp extract_property(_params) do
    {:error, "property is required. Use 'tahoe' or 'clear_lake'"}
  end

  defp extract_booking_ids(%{"booking_ids" => ids})
       when is_list(ids) and ids != [] do
    if Enum.all?(ids, &(is_binary(&1) or is_integer(&1))) do
      {:ok, ids}
    else
      {:error, "each booking_id must be a string or integer"}
    end
  end

  defp extract_booking_ids(%{"booking_ids" => _}) do
    {:error, "booking_ids must be a non-empty list"}
  end

  defp extract_booking_ids(_params) do
    {:error, "booking_ids is required"}
  end

  defp extract_rules_agreed(%{"rules_agreed" => true}), do: {:ok, true}

  defp extract_rules_agreed(%{"rules_agreed" => _}) do
    {:error, "rules_agreed must be true to complete check-in"}
  end

  defp extract_rules_agreed(_params) do
    {:error, "rules_agreed is required and must be true"}
  end

  defp resolve_bookings(ids, property) do
    bookings =
      Enum.reduce_while(ids, [], fn id, acc ->
        id_str = to_string(id)

        booking =
          case Bookings.get_booking_by_reference_id(id_str) do
            nil ->
              try do
                Bookings.get_booking!(id_str)
              rescue
                Ecto.NoResultsError -> nil
              end

            b ->
              b
          end

        cond do
          is_nil(booking) ->
            {:halt, {:error, "booking not found: #{id_str}"}}

          booking.property != property ->
            {:halt,
             {:error,
              "booking #{id_str} belongs to property '#{booking.property}', not '#{property}'"}}

          true ->
            {:cont, [booking | acc]}
        end
      end)

    case bookings do
      {:error, reason} -> {:error, reason}
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp extract_vehicles(%{"vehicles" => vehicles}) when is_list(vehicles) do
    if Enum.all?(vehicles, &is_map/1) do
      Enum.map(vehicles, fn v ->
        %{
          "type" => Map.get(v, "type", ""),
          "color" => Map.get(v, "color", ""),
          "make" => Map.get(v, "make", "")
        }
      end)
    else
      []
    end
  end

  defp extract_vehicles(_params), do: []
end
