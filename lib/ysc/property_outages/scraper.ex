defmodule Ysc.PropertyOutages.Scraper do
  @moduledoc """
  Service for scraping property outage information from different providers.

  Handles fetching outage data from various utility companies and updating
  the database with the latest outage information.
  """

  require Logger
  alias Ysc.PropertyOutages.OutageTracker
  alias Ysc.Repo
  alias Ysc.Bookings
  alias YscWeb.Emails.{Notifier, OutageNotification}

  @type provider :: :optimum | :pge | :scg | :liberty | :other

  # Optimum (Kubra.io) API endpoint for Tahoe property
  @optimum_api_url "https://kubra.io/cluster-data/300/f3329a2e-4d64-4800-b363-5c752421877e/f62a4326-f41f-4a4c-87d8-3ef912d07a16/public/cluster-2/02301012302231003.json"

  # Liberty Utilities API endpoint for Tahoe property
  @liberty_api_url "https://libertycf2-svc.smartcmobile.com/OutageAPI/api/1/Outage/GetAllOutages/?companyGroupCode=LUCA"
  @liberty_account_id "200008712503"

  @doc """
  Scrapes outages from all configured providers.
  """
  def scrape_all do
    Logger.info("Starting outage scraping for all providers")

    providers = get_providers()

    results =
      Enum.map(providers, fn provider ->
        Task.async(fn -> scrape_provider(provider) end)
      end)
      |> Enum.map(&Task.await/1)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Outage scraping completed",
      successful: successful,
      failed: failed,
      total_providers: length(providers)
    )

    {:ok, results}
  end

  @doc """
  Scrapes outages from a specific provider.
  """
  def scrape_provider(provider) do
    Logger.info("Scraping outages from provider", provider: provider)

    try do
      outages = fetch_outages_from_provider(provider)

      Logger.info("Processing outages for provider",
        provider: provider,
        count: length(outages)
      )

      results =
        Enum.map(outages, fn outage_data ->
          case upsert_outage(outage_data) do
            {:ok, outage} ->
              Logger.debug("Upserted outage",
                provider: provider,
                incident_id: outage.incident_id,
                incident_type: outage.incident_type
              )

              :ok

            {:error, changeset} ->
              Logger.error("Failed to upsert outage",
                provider: provider,
                incident_id: outage_data[:incident_id],
                errors: inspect(changeset.errors)
              )

              :error
          end
        end)

      successful = Enum.count(results, &(&1 == :ok))
      failed = Enum.count(results, &(&1 == :error))

      Logger.info("Successfully scraped outages from provider",
        provider: provider,
        total_outages: length(outages),
        successful_upserts: successful,
        failed_upserts: failed
      )

      {:ok, provider}
    rescue
      error ->
        error_info =
          if is_exception(error) do
            %{
              exception_type: error.__struct__,
              message: Exception.message(error)
            }
          else
            %{error: inspect(error)}
          end

        Logger.error(
          "Failed to scrape outages from provider",
          Map.merge(
            %{
              provider: provider,
              error: inspect(error),
              stacktrace: Exception.format_stacktrace(__STACKTRACE__)
            },
            error_info
          )
        )

        {:error, provider}
    end
  end

  # Private functions

  defp get_providers do
    # NOTE: Make this configurable via environment variables or database
    # For now, return a list of providers to scrape
    [:optimum, :liberty]
  end

  defp fetch_outages_from_provider(:optimum) do
    Logger.info("Fetching outages from Optimum (Kubra.io)",
      url: @optimum_api_url
    )

    case fetch_optimum_outages() do
      {:ok, outages} ->
        Logger.info("Successfully fetched Optimum outages",
          count: length(outages)
        )

        outages

      {:error, :not_found} ->
        Logger.info("No outages found (404 response from Optimum)")
        []

      {:error, reason} ->
        Logger.error("Failed to fetch Optimum outages",
          error: reason,
          error_type: inspect(reason),
          url: @optimum_api_url
        )

        []
    end
  end

  defp fetch_outages_from_provider(:pge) do
    # NOTE: Implement PG&E API scraping
    Logger.info("Fetching outages from PG&E")
    []
  end

  defp fetch_outages_from_provider(:scg) do
    # NOTE: Implement SCG (Southwest Gas) API scraping
    Logger.info("Fetching outages from SCG")
    []
  end

  defp fetch_outages_from_provider(:liberty) do
    Logger.info("Fetching outages from Liberty Utilities",
      url: @liberty_api_url
    )

    case fetch_liberty_outages() do
      {:ok, outages} ->
        Logger.info("Successfully fetched Liberty Utilities outages",
          count: length(outages)
        )

        outages

      {:error, :not_found} ->
        Logger.info("No outages found (404 response from Liberty Utilities)")
        []

      {:error, reason} ->
        Logger.error("Failed to fetch Liberty Utilities outages",
          error: reason,
          error_type: inspect(reason),
          url: @liberty_api_url
        )

        []
    end
  end

  defp fetch_outages_from_provider(provider) do
    Logger.warning("Unknown provider, skipping", provider: provider)
    []
  end

  # Optimum-specific scraping functions

  defp fetch_optimum_outages do
    headers = [
      {"accept", "application/json, text/plain, */*"},
      {"accept-encoding", "gzip, deflate, br, zstd"},
      {"accept-language", "en-US,en;q=0.9,sv-SE;q=0.8,sv;q=0.7"},
      {"cache-control", "no-cache"},
      {"dnt", "1"},
      {"pragma", "no-cache"},
      {"referer",
       "https://kubra.io/stormcenter/views/52993416-6665-4f4a-a5e9-bbff91b4fc3a?address=94102"},
      {"user-agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"}
    ]

    request = Finch.build(:get, @optimum_api_url, headers)

    case Finch.request(request, Ysc.Finch) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        # Check content-encoding header and decompress if needed
        # Finch returns headers as a list of {name, value} tuples
        content_encoding =
          headers
          |> Enum.find_value(fn
            {key, value} when is_binary(key) ->
              if String.downcase(key) == "content-encoding",
                do: String.downcase(value)

            {key, value} when is_atom(key) ->
              if String.downcase(Atom.to_string(key)) == "content-encoding",
                do: String.downcase(to_string(value))

            _ ->
              nil
          end)

        Logger.debug("Optimum API response headers",
          content_encoding: content_encoding,
          body_size: if(is_binary(body), do: byte_size(body), else: 0)
        )

        # Decompress the body if it's compressed
        decompressed_body =
          case content_encoding do
            encoding when encoding in ["gzip", "x-gzip"] ->
              decompress_gzip(body)

            "deflate" ->
              decompress_deflate(body)

            "br" ->
              decompress_brotli(body)

            "zstd" ->
              # Zstd not commonly available in Elixir, try to parse as-is first
              Logger.warning(
                "Zstd compression detected but may not be supported"
              )

              body

            _ ->
              # No compression or unknown - assume body is already decompressed
              body
          end

        # Log response body preview for debugging
        body_preview =
          if is_binary(decompressed_body) do
            decompressed_body
            |> String.slice(0, 500)
            |> String.replace(~r/\n/, " ")
          else
            inspect(decompressed_body)
          end

        Logger.debug("Optimum API response preview", body_preview: body_preview)

        case Jason.decode(decompressed_body) do
          {:ok, json} ->
            Logger.debug("Successfully parsed Optimum JSON",
              keys: Map.keys(json)
            )

            outages = parse_optimum_response(json, json)
            {:ok, outages}

          {:error, reason} ->
            Logger.error("Failed to parse Optimum JSON response",
              error: inspect(reason),
              body_preview: body_preview,
              body_length:
                if(is_binary(decompressed_body),
                  do: byte_size(decompressed_body),
                  else: 0
                )
            )

            {:error, :parse_error}
        end

      {:ok, %{status: 404}} ->
        Logger.info("Optimum API returned 404 - no outages")
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        body_preview =
          if is_binary(body) do
            body |> String.slice(0, 200)
          else
            inspect(body)
          end

        Logger.error("Unexpected status code from Optimum API",
          status: status,
          body_preview: body_preview
        )

        {:error, :unexpected_status}

      {:error, reason} ->
        error_details =
          case reason do
            %{__struct__: _} ->
              Map.from_struct(reason)
              |> Map.take([:reason, :message, :exception, :kind, :stacktrace])
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Map.new()

            map when is_map(map) ->
              map

            tuple when is_tuple(tuple) ->
              tuple

            other ->
              other
          end

        Logger.error("Network error fetching Optimum outages",
          error: inspect(reason),
          error_details: inspect(error_details),
          error_type: get_error_type(reason),
          url: @optimum_api_url
        )

        {:error, :network_error}
    end
  end

  defp parse_optimum_response(%{"file_data" => file_data}, raw_json)
       when is_list(file_data) do
    Enum.map(file_data, fn outage ->
      desc = outage["desc"] || %{}
      title = outage["title"] || "Outage"
      inc_id = desc["inc_id"] || "unknown_#{System.system_time(:second)}"

      # Parse ETR if available
      incident_date =
        case desc["etr"] do
          nil ->
            # Try to parse start_time if available
            parse_optimum_date(desc["start_time"])

          etr_string ->
            parse_optimum_date(etr_string)
        end || Date.utc_today()

      # Build description from available fields
      description_parts =
        [
          title,
          desc["cause"] && desc["cause"]["EN-US"],
          desc["crew_status"] && desc["crew_status"]["EN-US"],
          desc["comments"]
        ]
        |> Enum.filter(&(&1 != nil and &1 != ""))

      description =
        if Enum.empty?(description_parts) do
          "Internet outage"
        else
          Enum.join(description_parts, " - ")
        end

      %{
        incident_id: "optimum_#{inc_id}",
        incident_type: :internet_outage,
        company_name: "Optimum",
        description: description,
        incident_date: incident_date,
        property: :tahoe,
        raw_response: raw_json
      }
    end)
  end

  defp parse_optimum_response(_, _raw_json) do
    []
  end

  defp parse_optimum_date(nil), do: nil

  defp parse_optimum_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        DateTime.to_date(datetime)

      {:error, _} ->
        # Try parsing as just a date string
        case Date.from_iso8601(date_string) do
          {:ok, date} -> date
          {:error, _} -> nil
        end
    end
  end

  defp parse_optimum_date(_), do: nil

  # Liberty Utilities-specific scraping functions

  defp fetch_liberty_outages do
    Logger.debug("Building Liberty Utilities API request",
      url: @liberty_api_url,
      account_id: @liberty_account_id
    )

    headers = [
      {"accept", "application/json, text/plain, */*"},
      {"accept-encoding", "gzip, deflate"},
      {"accept-language", "en-US,en;q=0.9,sv-SE;q=0.8,sv;q=0.7"},
      {"cache-control", "no-cache"},
      {"dnt", "1"},
      {"origin", "https://myaccount.libertyenergyandwater.com"},
      {"pragma", "no-cache"},
      {"priority", "u=1, i"},
      {"referer", "https://myaccount.libertyenergyandwater.com/"},
      {"sec-ch-ua",
       ~S("Chromium";v="142", "Google Chrome";v="142", "Not_A Brand";v="99")},
      {"sec-ch-ua-mobile", "?0"},
      {"sec-ch-ua-platform", ~S("macOS")},
      {"sec-fetch-dest", "empty"},
      {"sec-fetch-mode", "cors"},
      {"sec-fetch-site", "cross-site"},
      {"st", "PL"},
      {"user-agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"}
    ]

    request = Finch.build(:get, @liberty_api_url, headers)

    Logger.debug("Sending Liberty Utilities API request",
      method: "GET",
      url: @liberty_api_url,
      header_count: length(headers)
    )

    case Finch.request(request, Ysc.Finch) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        # Check content-encoding header and decompress if needed
        # Finch returns headers as a list of {name, value} tuples
        content_encoding =
          headers
          |> Enum.find_value(fn
            {key, value} when is_binary(key) ->
              if String.downcase(key) == "content-encoding",
                do: String.downcase(value)

            {key, value} when is_atom(key) ->
              if String.downcase(Atom.to_string(key)) == "content-encoding",
                do: String.downcase(to_string(value))

            _ ->
              nil
          end)

        Logger.debug("Liberty Utilities API response headers",
          content_encoding: content_encoding,
          body_size: if(is_binary(body), do: byte_size(body), else: 0)
        )

        # Try to parse as JSON first (Finch might have already decompressed)
        # If content-encoding is present, we should still try decompression
        # but if JSON parsing works, we're good
        result =
          case Jason.decode(body) do
            {:ok, json} ->
              # Body is already decompressed and valid JSON
              Logger.debug("Body is already decompressed JSON")
              {:ok, json}

            {:error, _} ->
              # Try decompression if content-encoding indicates compression
              decompressed_body =
                case content_encoding do
                  encoding when encoding in ["gzip", "x-gzip"] ->
                    Logger.debug("Attempting gzip decompression")
                    decompress_gzip(body)

                  "deflate" ->
                    Logger.debug("Attempting deflate decompression")
                    decompress_deflate(body)

                  "br" ->
                    Logger.debug("Attempting brotli decompression")
                    decompress_brotli(body)

                  "zstd" ->
                    Logger.warning(
                      "Zstd compression detected but may not be supported"
                    )

                    body

                  _ ->
                    # No compression detected, but JSON parsing failed
                    # Log the body for debugging
                    Logger.warning(
                      "Content-encoding is nil/unknown but JSON parsing failed"
                    )

                    body
                end

              # Try parsing again after decompression
              case Jason.decode(decompressed_body) do
                {:ok, json} ->
                  Logger.debug("Successfully parsed after decompression")
                  {:ok, json}

                {:error, reason} ->
                  # Log detailed error information
                  body_preview =
                    if is_binary(decompressed_body) do
                      # Try to show first few bytes as hex for binary data
                      if String.valid?(decompressed_body) do
                        decompressed_body
                        |> String.slice(0, 500)
                        |> String.replace(~r/\n/, " ")
                      else
                        "Binary data (first 100 bytes): #{Base.encode16(:binary.part(decompressed_body, 0, min(100, byte_size(decompressed_body))))}"
                      end
                    else
                      inspect(decompressed_body)
                    end

                  Logger.error(
                    "Failed to parse Liberty Utilities JSON response",
                    error: inspect(reason),
                    content_encoding: content_encoding,
                    body_preview: body_preview,
                    body_length:
                      if(is_binary(decompressed_body),
                        do: byte_size(decompressed_body),
                        else: 0
                      )
                  )

                  {:error, :parse_error}
              end
          end

        case result do
          {:ok, json} ->
            Logger.debug("Successfully parsed Liberty Utilities JSON",
              keys: Map.keys(json)
            )

            outages = parse_liberty_response(json, json)
            {:ok, outages}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status: 404}} ->
        Logger.info("Liberty Utilities API returned 404 - no outages")
        {:error, :not_found}

      {:ok, %{status: status, body: body, headers: headers}} ->
        body_preview =
          if is_binary(body) do
            body |> String.slice(0, 200)
          else
            inspect(body)
          end

        # Extract relevant headers
        response_headers =
          headers
          |> Enum.map(fn
            {key, value} when is_binary(key) ->
              {String.downcase(key), value}

            {key, value} when is_atom(key) ->
              {String.downcase(Atom.to_string(key)), value}

            other ->
              other
          end)
          |> Enum.into(%{})

        Logger.error("Unexpected status code from Liberty Utilities API",
          status: status,
          url: @liberty_api_url,
          body_preview: body_preview,
          body_length: if(is_binary(body), do: byte_size(body), else: 0),
          response_headers: response_headers,
          account_id: @liberty_account_id
        )

        {:error, :unexpected_status}

      {:error, reason} ->
        error_details =
          case reason do
            %{__struct__: _} ->
              # It's a struct, extract useful fields
              Map.from_struct(reason)
              |> Map.take([:reason, :message, :exception, :kind, :stacktrace])
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Map.new()

            map when is_map(map) ->
              # It's already a map
              map

            tuple when is_tuple(tuple) ->
              # It's a tuple like {:error, reason}
              tuple

            other ->
              other
          end

        Logger.error("Network error fetching Liberty Utilities outages",
          error: inspect(reason),
          error_details: inspect(error_details),
          error_type: get_error_type(reason),
          url: @liberty_api_url,
          account_id: @liberty_account_id
        )

        {:error, :network_error}
    end
  end

  defp parse_liberty_response(%{"data" => data}, _raw_json)
       when is_list(data) do
    Logger.debug("Parsing Liberty Utilities response",
      total_incidents: length(data),
      account_id: @liberty_account_id
    )

    # Filter incidents that affect our account
    filtered_incidents =
      data
      |> Enum.filter(fn incident ->
        # Only check electricity outages (commodity_Type: "E")
        is_electricity = incident["commodity_Type"] == "E"

        has_account =
          has_account_in_affected_areas?(incident, @liberty_account_id)

        Logger.debug("Checking incident",
          incident_id: incident["incidentId"],
          commodity_type: incident["commodity_Type"],
          is_electricity: is_electricity,
          has_account: has_account,
          affected_areas_count:
            if(is_list(incident["affectedAreas"]),
              do: length(incident["affectedAreas"]),
              else: 0
            )
        )

        is_electricity && has_account
      end)

    Logger.info("Filtered Liberty Utilities incidents",
      total_incidents: length(data),
      electricity_incidents:
        Enum.count(data, fn i -> i["commodity_Type"] == "E" end),
      incidents_affecting_account: length(filtered_incidents),
      account_id: @liberty_account_id
    )

    filtered_incidents
    |> Enum.map(fn incident ->
      # Parse incident date from startTime
      incident_date =
        case incident["startTime"] do
          nil ->
            Date.utc_today()

          start_time_string ->
            parse_liberty_date(start_time_string) || Date.utc_today()
        end

      # Build description from available fields
      description_parts =
        [
          incident["description"],
          incident["cause_of_Outage"],
          incident["incident_remark"],
          incident["incident_status"]
        ]
        |> Enum.filter(&(&1 != nil and &1 != ""))

      description =
        if Enum.empty?(description_parts) do
          "Electricity outage"
        else
          Enum.join(description_parts, " - ")
        end

      # Extract only relevant incident data for storage
      # Filter affectedAreas to only include our account
      relevant_incident =
        incident
        |> Map.take([
          "incidentId",
          "name",
          "affectedCount",
          "description",
          "startTime",
          "restorationTime",
          "lastUpdateTime",
          "outage_Status",
          "notes",
          "lat",
          "lon",
          "crew_Status",
          "commodity_Type",
          "cause_of_Outage",
          "outageAttribute2",
          "incident_status",
          "incident_remark",
          "unrestoredcustomercount",
          "outageType",
          "isdefault"
        ])
        |> Map.put(
          "affectedAreas",
          filter_affected_areas_for_account(
            incident["affectedAreas"],
            @liberty_account_id
          )
        )

      %{
        incident_id: "liberty_#{incident["incidentId"]}",
        incident_type: :power_outage,
        company_name: "Liberty Utilities",
        description: description,
        incident_date: incident_date,
        property: :tahoe,
        raw_response: %{
          "status" => %{"type" => "success", "code" => 200},
          "data" => [relevant_incident]
        }
      }
    end)
  end

  defp parse_liberty_response(_, _raw_json) do
    Logger.warning("Liberty Utilities response does not match expected format",
      expected: "data array in response"
    )

    []
  end

  defp get_error_type(error) do
    cond do
      is_atom(error) -> "atom"
      is_tuple(error) -> "tuple"
      is_map(error) -> "map"
      is_binary(error) -> "string"
      true -> "unknown"
    end
  end

  defp has_account_in_affected_areas?(incident, account_id) do
    case incident["affectedAreas"] do
      areas when is_list(areas) ->
        Enum.any?(areas, fn area ->
          area["account_number"] == account_id
        end)

      _ ->
        false
    end
  end

  defp filter_affected_areas_for_account(affected_areas, account_id)
       when is_list(affected_areas) do
    Enum.filter(affected_areas, fn area ->
      area["account_number"] == account_id
    end)
  end

  defp filter_affected_areas_for_account(_, _), do: []

  defp parse_liberty_date(nil), do: nil

  defp parse_liberty_date(date_string) when is_binary(date_string) do
    # Liberty date format: "11/05/2025 09:42:47"
    # Try parsing as MM/DD/YYYY HH:MM:SS
    case Regex.run(
           ~r/(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2}):(\d{2})/,
           date_string
         ) do
      [_, month, day, year, _hour, _minute, _second] ->
        case Date.from_iso8601("#{year}-#{month}-#{day}") do
          {:ok, date} -> date
          {:error, _} -> nil
        end

      _ ->
        # Try parsing as ISO8601
        case DateTime.from_iso8601(date_string) do
          {:ok, datetime, _} ->
            DateTime.to_date(datetime)

          {:error, _} ->
            case Date.from_iso8601(date_string) do
              {:ok, date} -> date
              {:error, _} -> nil
            end
        end
    end
  end

  defp parse_liberty_date(_), do: nil

  # Decompression functions

  defp decompress_gzip(compressed_data) do
    try do
      compressed_data
      |> :zlib.gunzip()
    rescue
      error ->
        Logger.error("Failed to decompress gzip data", error: inspect(error))
        compressed_data
    end
  end

  defp decompress_deflate(compressed_data) do
    try do
      z = :zlib.open()
      :zlib.inflateInit(z)
      decompressed = :zlib.inflate(z, compressed_data)
      :zlib.close(z)
      IO.iodata_to_binary(decompressed)
    rescue
      error ->
        Logger.error("Failed to decompress deflate data", error: inspect(error))
        compressed_data
    end
  end

  defp decompress_brotli(compressed_data) do
    # Brotli decompression - Finch should handle this automatically,
    # but if it doesn't, we'll need a brotli library at runtime
    # For now, log a warning and try to parse as-is
    Logger.warning(
      "Brotli compression detected but runtime decompression not available. Finch should handle this automatically."
    )

    compressed_data
  end

  defp upsert_outage(outage_data) do
    incident_id = outage_data[:incident_id]

    # Check if outage already exists
    existing_outage = Repo.get_by(OutageTracker, incident_id: incident_id)

    case existing_outage do
      nil ->
        # Insert new outage
        changeset = OutageTracker.changeset(%OutageTracker{}, outage_data)

        case Repo.insert(changeset) do
          {:ok, outage} ->
            Logger.debug("Inserted new outage",
              incident_id: outage.incident_id,
              incident_type: outage.incident_type
            )

            # Notify active bookings about the new outage
            notify_active_bookings(outage)

            {:ok, outage}

          {:error, changeset} ->
            Logger.error("Failed to insert outage",
              incident_id: incident_id,
              errors: inspect(changeset.errors)
            )

            {:error, changeset}
        end

      existing ->
        # Update existing outage
        changeset = OutageTracker.changeset(existing, outage_data)

        case Repo.update(changeset) do
          {:ok, outage} ->
            Logger.debug("Updated existing outage",
              incident_id: outage.incident_id,
              incident_type: outage.incident_type
            )

            {:ok, outage}

          {:error, changeset} ->
            Logger.error("Failed to update outage",
              incident_id: incident_id,
              errors: inspect(changeset.errors)
            )

            {:error, changeset}
        end
    end
  end

  defp notify_active_bookings(outage) do
    Logger.info("Notifying active bookings about new outage",
      incident_id: outage.incident_id,
      property: outage.property,
      incident_date: outage.incident_date
    )

    # Get active bookings that overlap with the incident date
    active_bookings =
      get_active_bookings_for_outage(outage.property, outage.incident_date)

    Logger.info("Found active bookings for outage notification",
      count: length(active_bookings),
      property: outage.property,
      incident_date: outage.incident_date
    )

    Enum.each(active_bookings, fn booking ->
      send_outage_notification_email(booking, outage)
    end)
  end

  defp get_active_bookings_for_outage(property, incident_date) do
    # Get bookings that overlap with the incident date
    # A booking overlaps if: checkin_date <= incident_date < checkout_date
    Bookings.list_bookings(property, incident_date, incident_date)
    |> Enum.filter(fn booking ->
      booking.checkin_date <= incident_date and
        booking.checkout_date > incident_date
    end)
  end

  defp send_outage_notification_email(booking, outage) do
    # Ensure user is preloaded
    booking = Repo.preload(booking, :user)

    if booking.user && booking.user.email do
      # Use booking ID and incident type as idempotency key to prevent duplicate emails
      # This ensures we only send one email per booking per incident type per day
      # even if multiple incidents of the same type are detected
      idempotency_key = "outage_alert_#{booking.id}_#{outage.incident_type}"

      # Get user's first name or fallback to email
      first_name = booking.user.first_name || booking.user.email

      # Get cabin master information for the property
      cabin_master = OutageNotification.get_cabin_master(outage.property)

      cabin_master_name =
        if cabin_master do
          "#{cabin_master.first_name || ""} #{cabin_master.last_name || ""}"
          |> String.trim()
        else
          nil
        end

      cabin_master_phone =
        if cabin_master, do: cabin_master.phone_number, else: nil

      cabin_master_email =
        OutageNotification.get_cabin_master_email(outage.property)

      # Build email variables
      variables = %{
        first_name: first_name,
        property: outage.property,
        incident_type: outage.incident_type,
        company_name: outage.company_name,
        incident_date: outage.incident_date,
        description: outage.description,
        checkin_date: booking.checkin_date,
        checkout_date: booking.checkout_date,
        cabin_master_name: cabin_master_name,
        cabin_master_phone: cabin_master_phone,
        cabin_master_email: cabin_master_email
      }

      subject =
        "Property Outage Alert - #{OutageNotification.property_name(outage.property)}"

      # Create text body for email
      text_body = """
      Hej #{first_name},

      We wanted to let you know that a #{OutageNotification.incident_type_name(outage.incident_type)} has been reported at the #{OutageNotification.property_name(outage.property)}.

      Outage Details:
      - Type: #{OutageNotification.incident_type_name(outage.incident_type)}
      - Provider: #{outage.company_name}
      - Date: #{Calendar.strftime(outage.incident_date, "%B %d, %Y")}
      #{if outage.description, do: "- Description: #{outage.description}", else: ""}

      Your Booking:
      - Check-in: #{Calendar.strftime(booking.checkin_date, "%B %d, %Y")}
      - Check-out: #{Calendar.strftime(booking.checkout_date, "%B %d, %Y")}

      #{if cabin_master_name || cabin_master_email do
        "If you have any issues or need help, please reach out to the cabin master:\n\n" <> if(cabin_master_name, do: "- Cabin Master: #{cabin_master_name}\n", else: "") <> if(cabin_master_phone, do: "- Phone: #{cabin_master_phone}\n", else: "") <> if cabin_master_email, do: "- Email: #{cabin_master_email}\n", else: ""
      else
        ""
      end}

      We recommend checking the provider's outage map for the latest status and estimated restoration time.

      #{if OutageNotification.provider_outage_map_url(outage.company_name) do
        "View Outage Map: #{OutageNotification.provider_outage_map_url(outage.company_name)}"
      else
        ""
      end}

      Please note that outages can be unpredictable and restoration times may vary. We recommend checking the provider's website for the most up-to-date information.

      If you have any questions or concerns, please don't hesitate to reach out to us.

      The Young Scandinavians Club
      """

      case Notifier.schedule_email(
             booking.user.email,
             idempotency_key,
             subject,
             "outage_notification",
             variables,
             text_body,
             booking.user.id
           ) do
        %Oban.Job{} ->
          Logger.info("Scheduled outage notification email",
            booking_id: booking.id,
            user_email: booking.user.email,
            outage_id: outage.incident_id
          )

        {:error, reason} ->
          Logger.error("Failed to schedule outage notification email",
            booking_id: booking.id,
            user_email: booking.user.email,
            outage_id: outage.incident_id,
            error: inspect(reason)
          )
      end
    else
      Logger.warning(
        "Cannot send outage notification - booking has no user or email",
        booking_id: booking.id,
        outage_id: outage.incident_id
      )
    end
  end
end
