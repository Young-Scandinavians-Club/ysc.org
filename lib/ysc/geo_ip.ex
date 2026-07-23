defmodule Ysc.GeoIP do
  @moduledoc """
  IP geolocation lookups using the locus library with MaxMind GeoLite2.

  The loader is only started in deployed environments (sandbox or production)
  when a valid MaxMind license key is configured. Local dev and test never
  download the database. All functions degrade gracefully when the database
  is unavailable.
  """

  require Ysc.Logging

  @loader_name :city

  @doc """
  Returns true if a MaxMind license key is configured.
  """
  def configured? do
    case Application.get_env(:locus, :license_key) do
      key when is_binary(key) and byte_size(key) > 0 -> true
      _ -> false
    end
  end

  @doc """
  Looks up geolocation information for an IP address string.

  Returns a map with `:country`, `:region`, `:city`, `:latitude`, and
  `:longitude` keys, or an empty map if the lookup fails or the database
  is not available.
  """
  def lookup(ip_address) when is_binary(ip_address) do
    if configured?() do
      ip_address
      |> Ysc.IpAddress.normalize()
      |> case do
        nil -> %{}
        normalized -> do_lookup(normalized)
      end
    else
      %{}
    end
  end

  def lookup(_), do: %{}

  @doc """
  Parses a raw MaxMind GeoLite2-style map (as returned by `:locus`) into the
  compact map used by `lookup/1`.

  Exposed for unit tests and for callers that already have an entry map.
  """
  def parse_locus_entry(entry) when is_map(entry), do: parse_entry(entry)
  def parse_locus_entry(_), do: %{}

  # Private

  defp do_lookup(ip_address) do
    case apply(:locus, :lookup, [@loader_name, String.to_charlist(ip_address)]) do
      {:ok, entry} ->
        parse_entry(entry)

      :not_found ->
        %{}

      {:error, reason} ->
        Ysc.Logging.debug("GeoIP lookup failed",
          extra: %{ip: ip_address, reason: inspect(reason)}
        )

        %{}
    end
  rescue
    error ->
      Ysc.Logging.debug("GeoIP lookup raised exception",
        extra: %{ip: ip_address, error: inspect(error)}
      )

      %{}
  end

  defp parse_entry(entry) when is_map(entry) do
    country =
      get_in(entry, ["country", "iso_code"]) ||
        get_in(entry, ["registered_country", "iso_code"])

    region =
      get_in(entry, ["subdivisions"])
      |> List.wrap()
      |> List.first()
      |> then(fn
        nil ->
          nil

        subdivision ->
          get_in(subdivision, ["names", "en"]) ||
            get_in(subdivision, ["iso_code"])
      end)

    city = get_in(entry, ["city", "names", "en"])

    latitude = get_in(entry, ["location", "latitude"])
    longitude = get_in(entry, ["location", "longitude"])

    %{}
    |> put_if_present(:country, country)
    |> put_if_present(:region, region)
    |> put_if_present(:city, city)
    |> put_if_present(:latitude, latitude)
    |> put_if_present(:longitude, longitude)
  end

  defp parse_entry(_), do: %{}

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
end
