defmodule Ysc.PropertyOutages.Scraper do
  @moduledoc """
  Service for scraping property outage information from different providers.

  Handles fetching outage data from various utility companies and updating
  the database with the latest outage information.
  """

  import Ecto.Query

  require Ysc.Logging

  alias Ysc.Ci.QueryExplain.Fixtures
  alias Ysc.PropertyOutages.OutageTracker
  alias Ysc.Repo
  alias Ysc.Bookings
  alias YscWeb.Emails.{Notifier, OutageNotification}

  @type provider :: :optimum | :pge | :scg | :liberty | :other

  # Optimum (Kubra.io) StormCenter powering optimum.com/outage-map.
  # The actual outage data lives under a dataset id that Kubra rotates on
  # every publish cycle (observed every 15-60 min), so it cannot be
  # hardcoded - we resolve it fresh from `currentState` on every scrape
  # (its response embeds the view-cluster id and current dataset id in
  # `data.cluster_interval_generation_data`). The quadkey/bucket below
  # are stable identifiers for the map tile covering the Tahoe cabin
  # (2685 Cedar Lane, Homewood, CA 96141), reverse-engineered from the
  # public map.
  @optimum_stormcenter_id "741d8eb7-db4c-4ef1-b92a-7a4dd82f6e38"
  @optimum_view_id "52993416-6665-4f4a-a5e9-bbff91b4fc3a"
  @optimum_current_state_url "https://kubra.io/stormcenter/api/v1/stormcenters/#{@optimum_stormcenter_id}/views/#{@optimum_view_id}/currentState?preview=false"
  @optimum_quadkey_hash_bucket "300"
  @optimum_quadkey_filename "02301012302231003"

  # Liberty Utilities API endpoint for Tahoe property
  @liberty_api_url "https://libertycf2-svc.smartcmobile.com/OutageAPI/api/1/Outage/GetAllOutages/?companyGroupCode=LUCA"
  @liberty_account_id "200008712503"

  @doc """
  Scrapes outages from all configured providers.
  """
  def scrape_all do
    Ysc.Logging.info("Starting outage scraping for all providers")

    providers = get_providers()

    results =
      Enum.map(providers, fn provider ->
        Task.async(fn -> scrape_provider(provider) end)
      end)
      |> Enum.map(&Task.await/1)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Ysc.Logging.info("Outage scraping completed",
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
    Ysc.Logging.info("Scraping outages from provider", provider: provider)

    try do
      outages = fetch_outages_from_provider(provider)

      Ysc.Logging.info("Processing outages for provider",
        provider: provider,
        count: length(outages)
      )

      results =
        Enum.map(outages, fn outage_data ->
          case upsert_outage(outage_data) do
            {:ok, outage} ->
              Ysc.Logging.debug("Upserted outage",
                provider: provider,
                incident_id: outage.incident_id,
                incident_type: outage.incident_type
              )

              :ok

            {:error, changeset} ->
              Ysc.Logging.error("Failed to upsert outage",
                provider: provider,
                incident_id: outage_data[:incident_id],
                errors: inspect(changeset.errors)
              )

              :error
          end
        end)

      successful = Enum.count(results, &(&1 == :ok))
      failed = Enum.count(results, &(&1 == :error))

      Ysc.Logging.info("Successfully scraped outages from provider",
        provider: provider,
        total_outages: length(outages),
        successful_upserts: successful,
        failed_upserts: failed
      )

      {:ok, provider}
    rescue
      error ->
        Ysc.Logging.error(
          "Failed to scrape outages from provider",
          provider: provider,
          error: inspect(error),
          exception_type: error.__struct__,
          message: Exception.message(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
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
    Ysc.Logging.info("Fetching outages from Optimum (Kubra.io)",
      current_state_url: @optimum_current_state_url
    )

    case fetch_optimum_outages() do
      {:ok, outages} ->
        Ysc.Logging.info("Successfully fetched Optimum outages",
          count: length(outages)
        )

        outages

      {:error, :not_found} ->
        Ysc.Logging.info("No outages found (404 response from Optimum)")
        []

      {:error, reason} ->
        Ysc.Logging.error("Failed to fetch Optimum outages",
          error: reason,
          error_type: inspect(reason),
          current_state_url: @optimum_current_state_url
        )

        []
    end
  end

  defp fetch_outages_from_provider(:pge) do
    # NOTE: Implement PG&E API scraping
    Ysc.Logging.info("Fetching outages from PG&E")
    []
  end

  defp fetch_outages_from_provider(:scg) do
    # NOTE: Implement SCG (Southwest Gas) API scraping
    Ysc.Logging.info("Fetching outages from SCG")
    []
  end

  defp fetch_outages_from_provider(:liberty) do
    Ysc.Logging.info("Fetching outages from Liberty Utilities",
      url: @liberty_api_url
    )

    case fetch_liberty_outages() do
      {:ok, outages} ->
        Ysc.Logging.info("Successfully fetched Liberty Utilities outages",
          count: length(outages)
        )

        outages

      {:error, :not_found} ->
        Ysc.Logging.info(
          "No outages found (404 response from Liberty Utilities)"
        )

        []

      {:error, reason} ->
        Ysc.Logging.error("Failed to fetch Liberty Utilities outages",
          error: reason,
          error_type: inspect(reason),
          url: @liberty_api_url
        )

        []
    end
  end

  defp fetch_outages_from_provider(provider) do
    Ysc.Logging.warning("Unknown provider, skipping", provider: provider)
    []
  end

  # Optimum-specific scraping functions

  defp fetch_optimum_outages do
    case resolve_optimum_cluster_data_url() do
      {:ok, cluster_data_url} ->
        fetch_optimum_cluster_data(cluster_data_url)

      {:error, reason} ->
        Ysc.Logging.error("Failed to resolve current Optimum dataset",
          error: inspect(reason),
          current_state_url: @optimum_current_state_url
        )

        {:error, reason}
    end
  end

  # Kubra republishes outage data under a fresh dataset id on every cycle,
  # so we look up the current one instead of relying on a hardcoded URL
  # that inevitably goes stale (returns 404 for a dataset that no longer
  # exists, silently masking real outages).
  defp resolve_optimum_cluster_data_url do
    request = Finch.build(:get, @optimum_current_state_url, optimum_headers())

    with {:ok, %{status: 200, body: body}} <- Finch.request(request, Ysc.Finch),
         {:ok, json} <- Jason.decode(body),
         template when is_binary(template) <-
           get_in(json, ["data", "cluster_interval_generation_data"]) do
      {:ok, optimum_cluster_data_url(template)}
    else
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
      nil -> {:error, :missing_cluster_data_template}
    end
  end

  # Builds the Tahoe-cabin cluster JSON URL from Kubra's rotating
  # `cluster_interval_generation_data` template. `{qkh}` is replaced with
  # the stable quadkey hash bucket for 2685 Cedar Lane, Homewood, CA.
  @doc false
  def optimum_cluster_data_url(template) when is_binary(template) do
    path = String.replace(template, "{qkh}", @optimum_quadkey_hash_bucket)

    "https://kubra.io/#{path}/public/cluster-2/#{@optimum_quadkey_filename}.json"
  end

  defp optimum_headers do
    [
      {"accept", "application/json, text/plain, */*"},
      {"accept-encoding", "gzip, deflate, br, zstd"},
      {"accept-language", "en-US,en;q=0.9,sv-SE;q=0.8,sv;q=0.7"},
      {"cache-control", "no-cache"},
      {"dnt", "1"},
      {"pragma", "no-cache"},
      {"referer",
       "https://kubra.io/stormcenter/views/#{@optimum_view_id}?address=96141"},
      {"user-agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"}
    ]
  end

  defp fetch_optimum_cluster_data(cluster_data_url) do
    request = Finch.build(:get, cluster_data_url, optimum_headers())

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

        Ysc.Logging.debug("Optimum API response headers",
          content_encoding: content_encoding,
          body_size: byte_size(body)
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
              Ysc.Logging.warning(
                "Zstd compression detected but may not be supported"
              )

              body

            _ ->
              # No compression or unknown - assume body is already decompressed
              body
          end

        # Log response body preview for debugging
        body_preview = safe_body_preview(decompressed_body, 500)

        Ysc.Logging.debug("Optimum API response preview",
          body_preview: body_preview
        )

        case Jason.decode(decompressed_body) do
          {:ok, json} ->
            Ysc.Logging.debug("Successfully parsed Optimum JSON",
              keys: Map.keys(json)
            )

            outages = parse_optimum_response(json, json)
            {:ok, outages}

          {:error, reason} ->
            Ysc.Logging.error("Failed to parse Optimum JSON response",
              error: inspect(reason),
              body_preview: body_preview,
              body_length: byte_size(decompressed_body)
            )

            {:error, :parse_error}
        end

      {:ok, %{status: 404}} ->
        Ysc.Logging.info("Optimum API returned 404 - no outages")
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        body_preview = safe_body_preview(body, 200)

        Ysc.Logging.error("Unexpected status code from Optimum API",
          status: status,
          body_preview: body_preview
        )

        {:error, :unexpected_status}

      {:error, reason} ->
        error_details =
          Map.from_struct(reason)
          |> Map.take([:reason, :message, :exception, :kind, :stacktrace])
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        Ysc.Logging.error("Network error fetching Optimum outages",
          error: inspect(reason),
          error_details: inspect(error_details),
          error_type: get_error_type(reason),
          url: cluster_data_url
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
    Ysc.Logging.debug("Building Liberty Utilities API request",
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

    Ysc.Logging.debug("Sending Liberty Utilities API request",
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

        Ysc.Logging.debug("Liberty Utilities API response headers",
          content_encoding: content_encoding,
          body_size: byte_size(body)
        )

        # Try to parse as JSON first (Finch might have already decompressed)
        # If content-encoding is present, we should still try decompression
        # but if JSON parsing works, we're good
        result =
          case Jason.decode(body) do
            {:ok, json} ->
              # Body is already decompressed and valid JSON
              Ysc.Logging.debug("Body is already decompressed JSON")
              {:ok, json}

            {:error, _} ->
              # Try decompression if content-encoding indicates compression
              decompressed_body =
                case content_encoding do
                  encoding when encoding in ["gzip", "x-gzip"] ->
                    Ysc.Logging.debug("Attempting gzip decompression")
                    decompress_gzip(body)

                  "deflate" ->
                    Ysc.Logging.debug("Attempting deflate decompression")
                    decompress_deflate(body)

                  "br" ->
                    Ysc.Logging.debug("Attempting brotli decompression")
                    decompress_brotli(body)

                  "zstd" ->
                    Ysc.Logging.warning(
                      "Zstd compression detected but may not be supported"
                    )

                    body

                  _ ->
                    # No compression detected, but JSON parsing failed
                    # Log the body for debugging
                    Ysc.Logging.warning(
                      "Content-encoding is nil/unknown but JSON parsing failed"
                    )

                    body
                end

              # Try parsing again after decompression
              case Jason.decode(decompressed_body) do
                {:ok, json} ->
                  Ysc.Logging.debug("Successfully parsed after decompression")
                  {:ok, json}

                {:error, reason} ->
                  # Log detailed error information
                  body_preview = safe_body_preview(decompressed_body, 500)

                  Ysc.Logging.error(
                    "Failed to parse Liberty Utilities JSON response",
                    error: inspect(reason),
                    content_encoding: content_encoding,
                    body_preview: body_preview,
                    body_length: byte_size(decompressed_body)
                  )

                  {:error, :parse_error}
              end
          end

        case result do
          {:ok, json} ->
            Ysc.Logging.debug("Successfully parsed Liberty Utilities JSON",
              keys: Map.keys(json)
            )

            outages = parse_liberty_response(json, json)
            {:ok, outages}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status: 404}} ->
        Ysc.Logging.info("Liberty Utilities API returned 404 - no outages")
        {:error, :not_found}

      {:ok, %{status: status, body: body, headers: headers}} ->
        body_preview = safe_body_preview(body, 200)

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

        Ysc.Logging.error("Unexpected status code from Liberty Utilities API",
          status: status,
          url: @liberty_api_url,
          body_preview: body_preview,
          body_length: byte_size(body),
          response_headers: response_headers,
          account_id: @liberty_account_id
        )

        {:error, :unexpected_status}

      {:error, reason} ->
        error_details =
          Map.from_struct(reason)
          |> Map.take([:reason, :message, :exception, :kind, :stacktrace])
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        Ysc.Logging.error("Network error fetching Liberty Utilities outages",
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
    Ysc.Logging.debug("Parsing Liberty Utilities response",
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

        Ysc.Logging.debug("Checking incident",
          incident_id: incident["incidentId"],
          commodity_type: incident["commodity_Type"],
          is_electricity: is_electricity,
          has_account: has_account,
          affected_areas_count: length(incident["affectedAreas"] || [])
        )

        is_electricity && has_account
      end)

    Ysc.Logging.info("Filtered Liberty Utilities incidents",
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
    Ysc.Logging.warning(
      "Liberty Utilities response does not match expected format",
      expected: "data array in response"
    )

    []
  end

  @dialyzer {:nowarn_function, get_error_type: 1}
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
        Ysc.Logging.error("Failed to decompress gzip data",
          error: inspect(error)
        )

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
        Ysc.Logging.error("Failed to decompress deflate data",
          error: inspect(error)
        )

        compressed_data
    end
  end

  defp decompress_brotli(compressed_data) do
    # Brotli decompression - Finch should handle this automatically,
    # but if it doesn't, we'll need a brotli library at runtime
    # For now, log a warning and try to parse as-is
    Ysc.Logging.warning(
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
            Ysc.Logging.debug("Inserted new outage",
              incident_id: outage.incident_id,
              incident_type: outage.incident_type
            )

            # Notify active bookings about the new outage
            notify_active_bookings(outage)

            {:ok, outage}

          {:error, changeset} ->
            Ysc.Logging.error("Failed to insert outage",
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
            Ysc.Logging.debug("Updated existing outage",
              incident_id: outage.incident_id,
              incident_type: outage.incident_type
            )

            {:ok, outage}

          {:error, changeset} ->
            Ysc.Logging.error("Failed to update outage",
              incident_id: incident_id,
              errors: inspect(changeset.errors)
            )

            {:error, changeset}
        end
    end
  end

  defp notify_active_bookings(outage) do
    Ysc.Logging.info("Notifying active bookings about new outage",
      incident_id: outage.incident_id,
      property: outage.property,
      incident_date: outage.incident_date
    )

    # Get active bookings that overlap with the incident date
    active_bookings =
      get_active_bookings_for_outage(outage.property, outage.incident_date)

    Ysc.Logging.info("Found active bookings for outage notification",
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

      variables =
        OutageNotification.build_notification_variables(booking, outage)

      subject = OutageNotification.get_subject(outage.property)

      text_body = OutageNotification.text_body(variables)

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
          Ysc.Logging.info("Scheduled outage notification email",
            booking_id: booking.id,
            user_email: booking.user.email,
            outage_id: outage.incident_id
          )

        {:error, reason} ->
          Ysc.Logging.error("Failed to schedule outage notification email",
            booking_id: booking.id,
            user_email: booking.user.email,
            outage_id: outage.incident_id,
            error: inspect(reason)
          )
      end
    else
      Ysc.Logging.warning(
        "Cannot send outage notification - booking has no user or email",
        booking_id: booking.id,
        outage_id: outage.incident_id
      )
    end
  end

  defp safe_body_preview(body, limit) when is_binary(body) do
    if String.valid?(body) do
      body
      |> String.slice(0, limit)
      |> String.replace(~r/\n/, " ")
    else
      "Binary data (first 100 bytes): #{Base.encode16(:binary.part(body, 0, min(100, byte_size(body))))}"
    end
  end

  @doc false
  def ci_query_explain_query do
    incident_id = Fixtures.ulid()

    from(o in OutageTracker, where: o.incident_id == ^incident_id)
  end
end
