defmodule YscWeb.Api.BookingsController do
  @moduledoc """
  REST API controller for booking-related operations.

  Supports both Tahoe and Clear Lake properties via the `property` query parameter.
  """
  use YscWeb, :controller

  alias Ysc.Bookings

  action_fallback YscWeb.Api.FallbackController

  @valid_properties ~w(tahoe clear_lake)

  # Default kiosk listing window when dates are omitted: recent past through near future.
  # Prevents unbounded export of full booking history if the shared bearer token leaks.
  @default_index_past_days 7
  @default_index_future_days 30

  @doc """
  List bookings for a given property and optional date range.

  Query params:
    - property: "tahoe" or "clear_lake" (required)
    - start_date: ISO 8601 date string (optional, defaults to 7 days ago)
    - end_date: ISO 8601 date string (optional, defaults to 30 days ahead)
  """
  def index(conn, params) do
    today = Date.utc_today()
    default_start = Date.add(today, -@default_index_past_days)
    default_end = Date.add(today, @default_index_future_days)

    with {:ok, property} <- parse_property(params),
         {:ok, start_date} <- parse_date(params, "start_date", default_start),
         {:ok, end_date} <- parse_date(params, "end_date", default_end) do
      bookings =
        Bookings.list_bookings(property, start_date, end_date,
          preload: [
            :rooms,
            {:user, :current_avatar},
            :booking_guests,
            check_ins: :check_in_vehicles
          ]
        )

      render(conn, :index, bookings: bookings)
    end
  end

  @doc """
  Calendar view of bookings - returns bookings grouped by date.

  Query params:
    - property: "tahoe" or "clear_lake" (required)
    - start_date: ISO 8601 date string (optional, defaults to today)
    - end_date: ISO 8601 date string (optional, defaults to 30 days from today)
  """
  def calendar(conn, params) do
    today = Date.utc_today()
    default_start = today
    default_end = Date.add(today, 30)

    with {:ok, property} <- parse_property(params),
         {:ok, start_date} <- parse_date(params, "start_date", default_start),
         {:ok, end_date} <- parse_date(params, "end_date", default_end) do
      bookings =
        Bookings.list_bookings(property, start_date, end_date,
          preload: [
            :rooms,
            {:user, :current_avatar},
            :booking_guests,
            check_ins: :check_in_vehicles
          ]
        )

      render(conn, :calendar,
        bookings: bookings,
        start_date: start_date,
        end_date: end_date
      )
    end
  end

  @doc """
  Lookup bookings by last name, optionally filtered by property.

  Query params:
    - last_name: guest or member last name (required)
    - property: "tahoe" or "clear_lake" (optional, defaults to "tahoe")
  """
  def lookup(conn, params) do
    last_name = String.trim(Map.get(params, "last_name", ""))

    if last_name == "" do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "last_name is required"})
    else
      with {:ok, property} <-
             parse_property(Map.put_new(params, "property", "tahoe")) do
        bookings = Bookings.search_bookings_by_last_name(last_name, property)
        render(conn, :index, bookings: bookings)
      end
    end
  end

  defp parse_property(%{"property" => property})
       when property in @valid_properties do
    {:ok, String.to_existing_atom(property)}
  end

  defp parse_property(%{"property" => _invalid}) do
    {:error, :invalid_property}
  end

  defp parse_property(_params) do
    {:error, :missing_property}
  end

  defp parse_date(params, key, default) do
    case Map.get(params, key) do
      nil ->
        {:ok, default}

      "" ->
        {:ok, default}

      date_str ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> {:ok, date}
          {:error, _} -> {:error, {:invalid_date, key}}
        end
    end
  end
end
