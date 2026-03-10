defmodule Ysc.WpMigration.Load do
  @moduledoc """
  Phase 2 load: reads the export directory and loads users, applications,
  media (upload to blob + create Image), posts, and Stripe data into Postgres.
  """

  require Ysc.Logging
  import Ecto.Query
  alias Ysc.Repo
  alias Ysc.Accounts.{User, Address, SignupApplication}
  alias Ysc.Media
  alias Ysc.Media.Image
  alias Ysc.Posts.Post
  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, Room, BookingGuest}
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription
  alias Ysc.Payments
  alias Ysc.Customers
  alias YscWeb.Workers.ImageProcessor
  alias Ysc.WpMigration.HtmlTransformer

  @doc """
  Runs the load. Reads export_dir (users.json, applications.json, posts.json, media/, stripe_customer_lookup.json)
  and inserts into the app DB. Optionally uploads media to S3 and creates Image records.

  Options:
  - :export_dir - path to export directory (required)
  - :dry_run - if true, do not write to DB or S3
  - :upload_media - if true, upload media folder to S3 and create Images (default: true)
  - :create_stripe_subscriptions - if true, create real Stripe customers and subscriptions
      in the connected Stripe account (useful for sandbox/dev testing). Each subscription
      uses trial_end set to the WP renewal date so no charge fires immediately.
  """
  def run(opts \\ []) do
    export_dir = opts[:export_dir]
    dry_run = opts[:dry_run] || false
    upload_media = Keyword.get(opts, :upload_media, true)
    create_stripe_subscriptions = opts[:create_stripe_subscriptions] || false

    if export_dir do
      export_dir = Path.expand(export_dir)

      if File.dir?(export_dir) do
        do_run(export_dir, dry_run, upload_media, create_stripe_subscriptions)
      else
        {:error, "Export directory not found: #{export_dir}"}
      end
    else
      {:error, "Missing :export_dir"}
    end
  end

  defp do_run(export_dir, dry_run, upload_media, create_stripe_subscriptions) do
    users_json = Path.join(export_dir, "users.json")
    applications_json = Path.join(export_dir, "applications.json")
    posts_json = Path.join(export_dir, "posts.json")
    stripe_json = Path.join(export_dir, "stripe_customer_lookup.json")
    bookings_json = Path.join(export_dir, "bookings.json")
    media_dir = Path.join(export_dir, "media")

    users_data = read_json(users_json)
    applications_data = read_json(applications_json)
    posts_data = read_json(posts_json)
    stripe_data = read_json(stripe_json)
    bookings_data = read_json(bookings_json)

    if dry_run do
      Ysc.Logging.info(
        "Dry run: would load #{length(users_data)} users, #{length(applications_data)} applications, #{length(posts_data)} posts"
      )

      {:ok, %{}}
    else
      # Resolve migration uploader (first admin) for Image.user_id
      uploader = get_migration_uploader()

      {:ok, user_map} = load_users(users_data)
      {:ok, _} = load_applications(applications_data, user_map)

      {:ok, image_map} =
        if upload_media and File.dir?(media_dir),
          do: load_media(media_dir, uploader),
          else: {:ok, %{}}

      {:ok, _} = load_posts(posts_data, user_map, image_map)

      if stripe_data && stripe_data != [],
        do: load_stripe(stripe_data, user_map)

      load_subscriptions(users_data, user_map, create_stripe_subscriptions)

      if bookings_data && bookings_data != [],
        do: load_bookings(bookings_data, user_map)

      {:ok, %{user_map: user_map, image_map: image_map}}
    end
  end

  defp read_json(path) do
    if File.exists?(path) do
      path |> File.read!() |> Jason.decode!()
    else
      []
    end
  end

  defp get_migration_uploader do
    case Repo.one(from u in User, where: u.role == ^:admin, limit: 1) do
      nil -> Repo.one(from u in User, limit: 1)
      user -> user
    end
  end

  defp load_users(users_data) do
    user_map = %{}

    Enum.reduce_while(users_data, {:ok, user_map}, fn row, {:ok, acc} ->
      email = row["email"]
      if is_nil(email) or email == "", do: {:cont, {:ok, acc}}

      case Ysc.Accounts.get_user_by_email(email) do
        existing when not is_nil(existing) ->
          # Idempotent: update profile from export when re-running
          update_attrs =
            %{
              "first_name" =>
                row["first_name"] || row["display_name"] || "Unknown",
              "last_name" => row["last_name"] || "User",
              "phone_number" => normalize_phone(row["phone_number"]),
              "most_connected_country" =>
                normalize_country(
                  row["most_connected_country"] ||
                    row["nordic_country_connected"] ||
                    row["Country"]
                )
            }
            |> maybe_put_date_of_birth(row)

          case existing
               |> User.update_user_changeset(update_attrs)
               |> backdate_timestamp(row["user_registered"])
               |> Repo.update() do
            {:ok, _} ->
              upsert_address(existing.id, row)
              {:cont, {:ok, Map.put(acc, row["wp_user_id"], existing.id)}}

            {:error, _} ->
              upsert_address(existing.id, row)
              {:cont, {:ok, Map.put(acc, row["wp_user_id"], existing.id)}}
          end

        nil ->
          state = map_account_status(row["account_status"])
          role = map_role(row["role"])

          attrs =
            %{
              "email" => email,
              "first_name" =>
                row["first_name"] || row["display_name"] || "Unknown",
              "last_name" => row["last_name"] || "User",
              "phone_number" => normalize_phone(row["phone_number"]),
              "state" => state,
              "role" => role,
              "most_connected_country" =>
                normalize_country(
                  row["most_connected_country"] ||
                    row["nordic_country_connected"] ||
                    row["Country"]
                )
            }
            |> maybe_put_date_of_birth(row)

          changeset =
            %User{}
            |> User.registration_changeset(attrs,
              require_password: false,
              validate_email: false,
              hash_password: false
            )
            |> backdate_timestamp(row["user_registered"])

          case Repo.insert(changeset) do
            {:ok, user} ->
              upsert_address(user.id, row)
              {:cont, {:ok, Map.put(acc, row["wp_user_id"], user.id)}}

            {:error, changeset} ->
              Ysc.Logging.warning("Failed to insert user",
                email: email,
                errors: inspect(changeset.errors)
              )

              # Skip users that fail validation rather than halting the entire
              # migration. The user can be corrected and re-imported on a re-run.
              {:cont, {:ok, acc}}
          end
      end
    end)
  end

  # Normalises WP phone numbers to E.164 format for storage.
  #
  # WP members entered numbers in many formats: "415-555-1234", "(415) 555-1234",
  # "4155551234", "+1 415 555 1234", international numbers with or without "+", etc.
  # ExPhoneNumber needs a region hint to parse numbers that lack a country code prefix;
  # "US" is used as the default since the membership is SF Bay Area based.
  #
  # Returns nil for nil/empty input and for numbers that cannot be parsed or are
  # not valid, so callers receive nil rather than an invalid string.
  defp normalize_phone(nil), do: nil
  defp normalize_phone(""), do: nil

  defp normalize_phone(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    if trimmed == "" do
      nil
    else
      case ExPhoneNumber.parse(trimmed, "US") do
        {:ok, phone} ->
          if ExPhoneNumber.is_valid_number?(phone),
            do: ExPhoneNumber.format(phone, :e164),
            else: nil

        {:error, _} ->
          nil
      end
    end
  end

  # Adds "date_of_birth" to the attrs map if we have a parseable date from WP.
  # Falls back through birth_date → application birth_date → nil.
  # Only sets the key when a valid date is found so we never overwrite an
  # existing date_of_birth with nil on re-runs.
  defp maybe_put_date_of_birth(attrs, row) do
    raw = row["birth_date"] || row["Birth Date"] || row["birthdate"]

    case parse_date(raw) do
      nil -> attrs
      date -> Map.put(attrs, "date_of_birth", date)
    end
  end

  defp upsert_address(user_id, row) do
    # The extract writes lowercase keys to users.json; some older code paths
    # used capitalised versions — check both to be safe.
    address_str =
      row["address"] || row["Address"] ||
        row["billing_address_1"]

    country =
      normalize_country(row["country"] || row["Country"])

    city =
      row["city"] || row["City"]

    region =
      row["state"] || row["State"] || row["region"] || row["Region"]

    postal_code =
      row["zip"] || row["postal_code"] || row["Zip code"] || row["postal"]

    unless is_nil_or_empty(address_str) or is_nil_or_empty(country) do
      attrs = %{
        user_id: user_id,
        address: address_str,
        city: city,
        region: region,
        postal_code: postal_code,
        country: country
      }

      existing = Repo.get_by(Address, user_id: user_id)

      result =
        if existing do
          existing |> Address.migration_changeset(attrs) |> Repo.update()
        else
          %Address{} |> Address.migration_changeset(attrs) |> Repo.insert()
        end

      case result do
        {:ok, _} ->
          :ok

        {:error, cs} ->
          Ysc.Logging.warning("Failed to upsert address",
            user_id: user_id,
            errors: inspect(cs.errors)
          )
      end
    end
  end

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_), do: false

  # Set of all valid ISO 3166-1 alpha-2 codes (used for fast 2-letter lookups).
  @country_code_set Map.new(
                      [
                        "AD",
                        "AE",
                        "AF",
                        "AG",
                        "AI",
                        "AL",
                        "AM",
                        "AO",
                        "AR",
                        "AT",
                        "AU",
                        "AW",
                        "AZ",
                        "BA",
                        "BB",
                        "BD",
                        "BE",
                        "BF",
                        "BG",
                        "BH",
                        "BI",
                        "BJ",
                        "BM",
                        "BN",
                        "BO",
                        "BR",
                        "BS",
                        "BT",
                        "BW",
                        "BY",
                        "BZ",
                        "CA",
                        "CD",
                        "CF",
                        "CG",
                        "CH",
                        "CI",
                        "CK",
                        "CL",
                        "CM",
                        "CN",
                        "CO",
                        "CR",
                        "CU",
                        "CV",
                        "CY",
                        "CZ",
                        "DE",
                        "DJ",
                        "DK",
                        "DM",
                        "DO",
                        "DZ",
                        "EC",
                        "EE",
                        "EG",
                        "ER",
                        "ES",
                        "ET",
                        "FI",
                        "FJ",
                        "FM",
                        "FR",
                        "GA",
                        "GB",
                        "GD",
                        "GE",
                        "GH",
                        "GM",
                        "GN",
                        "GQ",
                        "GR",
                        "GT",
                        "GW",
                        "GY",
                        "HN",
                        "HR",
                        "HT",
                        "HU",
                        "ID",
                        "IE",
                        "IL",
                        "IN",
                        "IQ",
                        "IR",
                        "IS",
                        "IT",
                        "JM",
                        "JO",
                        "JP",
                        "KE",
                        "KG",
                        "KH",
                        "KI",
                        "KM",
                        "KN",
                        "KP",
                        "KR",
                        "KW",
                        "KY",
                        "KZ",
                        "LA",
                        "LB",
                        "LC",
                        "LI",
                        "LK",
                        "LR",
                        "LS",
                        "LT",
                        "LU",
                        "LV",
                        "LY",
                        "MA",
                        "MC",
                        "MD",
                        "ME",
                        "MG",
                        "MH",
                        "MK",
                        "ML",
                        "MM",
                        "MN",
                        "MR",
                        "MT",
                        "MU",
                        "MV",
                        "MW",
                        "MX",
                        "MY",
                        "MZ",
                        "NA",
                        "NE",
                        "NG",
                        "NI",
                        "NL",
                        "NO",
                        "NP",
                        "NR",
                        "NZ",
                        "OM",
                        "PA",
                        "PE",
                        "PG",
                        "PH",
                        "PK",
                        "PL",
                        "PT",
                        "PW",
                        "PY",
                        "QA",
                        "RO",
                        "RS",
                        "RU",
                        "RW",
                        "SA",
                        "SB",
                        "SC",
                        "SD",
                        "SE",
                        "SG",
                        "SI",
                        "SK",
                        "SL",
                        "SM",
                        "SN",
                        "SO",
                        "SR",
                        "SS",
                        "ST",
                        "SV",
                        "SY",
                        "SZ",
                        "TD",
                        "TG",
                        "TH",
                        "TJ",
                        "TL",
                        "TM",
                        "TN",
                        "TO",
                        "TR",
                        "TT",
                        "TV",
                        "TZ",
                        "UA",
                        "UG",
                        "US",
                        "UY",
                        "UZ",
                        "VA",
                        "VC",
                        "VE",
                        "VN",
                        "VU",
                        "WS",
                        "YE",
                        "ZA",
                        "ZM",
                        "ZW"
                      ],
                      fn code -> {code, true} end
                    )

  # Comprehensive name → ISO 2-letter lookup.
  # Keys are downcased; values are uppercase ISO codes.
  @country_lookup %{
    # ── Nordic / Scandinavian (priority) ──────────────────────────────────────
    "norway" => "NO",
    "norge" => "NO",
    "norsk" => "NO",
    "nor" => "NO",
    "norwegian" => "NO",
    "sweden" => "SE",
    "sverige" => "SE",
    "svensk" => "SE",
    "swe" => "SE",
    "swedish" => "SE",
    "denmark" => "DK",
    "danmark" => "DK",
    "dansk" => "DK",
    "dnk" => "DK",
    "danish" => "DK",
    "finland" => "FI",
    "suomi" => "FI",
    "finska" => "FI",
    "fin" => "FI",
    "finnish" => "FI",
    "iceland" => "IS",
    "island" => "IS",
    "ísland" => "IS",
    "isl" => "IS",
    "icelandic" => "IS",
    # ── Other European ────────────────────────────────────────────────────────
    "united kingdom" => "GB",
    "uk" => "GB",
    "england" => "GB",
    "great britain" => "GB",
    "britain" => "GB",
    "gbr" => "GB",
    "scotland" => "GB",
    "wales" => "GB",
    "germany" => "DE",
    "deutschland" => "DE",
    "deu" => "DE",
    "france" => "FR",
    "fra" => "FR",
    "italy" => "IT",
    "italia" => "IT",
    "ita" => "IT",
    "spain" => "ES",
    "españa" => "ES",
    "esp" => "ES",
    "netherlands" => "NL",
    "holland" => "NL",
    "nld" => "NL",
    "switzerland" => "CH",
    "schweiz" => "CH",
    "che" => "CH",
    "austria" => "AT",
    "österreich" => "AT",
    "aut" => "AT",
    "belgium" => "BE",
    "belgique" => "BE",
    "bel" => "BE",
    "portugal" => "PT",
    "prt" => "PT",
    "poland" => "PL",
    "polska" => "PL",
    "pol" => "PL",
    "czech republic" => "CZ",
    "czechia" => "CZ",
    "cze" => "CZ",
    "hungary" => "HU",
    "hun" => "HU",
    "romania" => "RO",
    "rou" => "RO",
    "greece" => "GR",
    "grc" => "GR",
    "russia" => "RU",
    "rus" => "RU",
    "ukraine" => "UA",
    "ukr" => "UA",
    "ireland" => "IE",
    "ire" => "IE",
    "luxembourg" => "LU",
    "lux" => "LU",
    "estonia" => "EE",
    "est" => "EE",
    "latvia" => "LV",
    "lva" => "LV",
    "lithuania" => "LT",
    "ltu" => "LT",
    "croatia" => "HR",
    "hrv" => "HR",
    "serbia" => "RS",
    "srb" => "RS",
    "slovakia" => "SK",
    "svk" => "SK",
    "slovenia" => "SI",
    "svn" => "SI",
    "bulgaria" => "BG",
    "bgr" => "BG",
    "albania" => "AL",
    "alb" => "AL",
    "north macedonia" => "MK",
    "macedonia" => "MK",
    "bosnia" => "BA",
    "bih" => "BA",
    "montenegro" => "ME",
    "mne" => "ME",
    "cyprus" => "CY",
    "cyp" => "CY",
    "malta" => "MT",
    "mlt" => "MT",
    "liechtenstein" => "LI",
    "lie" => "LI",
    "monaco" => "MC",
    "mco" => "MC",
    "san marino" => "SM",
    "smr" => "SM",
    "andorra" => "AD",
    "and" => "AD",
    "moldova" => "MD",
    "mda" => "MD",
    # ── Americas ──────────────────────────────────────────────────────────────
    "united states" => "US",
    "usa" => "US",
    "u.s.a." => "US",
    "u.s." => "US",
    "america" => "US",
    "us" => "US",
    "canada" => "CA",
    "can" => "CA",
    "mexico" => "MX",
    "méxico" => "MX",
    "mex" => "MX",
    "brazil" => "BR",
    "brasil" => "BR",
    "bra" => "BR",
    "argentina" => "AR",
    "arg" => "AR",
    "chile" => "CL",
    "chl" => "CL",
    "colombia" => "CO",
    "col" => "CO",
    "peru" => "PE",
    "per" => "PE",
    "venezuela" => "VE",
    "ven" => "VE",
    "ecuador" => "EC",
    "ecu" => "EC",
    "costa rica" => "CR",
    "cri" => "CR",
    "panama" => "PA",
    "pan" => "PA",
    # ── Asia-Pacific ──────────────────────────────────────────────────────────
    "australia" => "AU",
    "aus" => "AU",
    "new zealand" => "NZ",
    "nzl" => "NZ",
    "japan" => "JP",
    "jpn" => "JP",
    "china" => "CN",
    "chn" => "CN",
    "india" => "IN",
    "ind" => "IN",
    "south korea" => "KR",
    "korea" => "KR",
    "kor" => "KR",
    "singapore" => "SG",
    "sgp" => "SG",
    "hong kong" => "HK",
    "hkg" => "HK",
    "taiwan" => "TW",
    "twn" => "TW",
    "indonesia" => "ID",
    "idn" => "ID",
    "malaysia" => "MY",
    "mys" => "MY",
    "thailand" => "TH",
    "tha" => "TH",
    "vietnam" => "VN",
    "vnm" => "VN",
    "philippines" => "PH",
    "phl" => "PH",
    # ── Middle East / Africa ──────────────────────────────────────────────────
    "israel" => "IL",
    "isr" => "IL",
    "turkey" => "TR",
    "türkiye" => "TR",
    "tur" => "TR",
    "south africa" => "ZA",
    "zaf" => "ZA",
    "egypt" => "EG",
    "egy" => "EG",
    "nigeria" => "NG",
    "nga" => "NG",
    "kenya" => "KE",
    "ken" => "KE",
    "ghana" => "GH",
    "gha" => "GH",
    "ethiopia" => "ET",
    "eth" => "ET",
    "united arab emirates" => "AE",
    "uae" => "AE",
    "are" => "AE"
  }

  # Normalizes a country string to an ISO 3166-1 alpha-2 code (e.g. "NO", "SE").
  # Handles: already-correct codes, 3-letter ISO codes, full English names,
  # native names, common abbreviations/typos, and slight misspellings via
  # Jaro-Winkler similarity.  Returns nil for unrecognised values so we never
  # silently store garbage.
  defp normalize_country(nil), do: nil
  defp normalize_country(""), do: nil

  defp normalize_country(raw) when is_binary(raw) do
    normalized = raw |> String.trim() |> String.upcase()

    cond do
      # Already a valid 2-letter code — accept as-is
      String.length(normalized) == 2 and
          Map.has_key?(@country_code_set, normalized) ->
        normalized

      true ->
        key = raw |> String.trim() |> String.downcase()

        case Map.get(@country_lookup, key) do
          nil -> fuzzy_match_country(key)
          code -> code
        end
    end
  end

  defp normalize_country(_), do: nil

  # Fuzzy-matches a downcased string against all names in @country_lookup using
  # Jaro-Winkler similarity.  Only considers lookup keys >= 4 chars to prevent
  # short abbreviations ("fin", "nor", "swe") from distorting results.
  # Requires a score >= 0.90 to accept the match.
  @fuzzy_country_candidates Enum.filter(
                              Map.keys(%{
                                "norway" => nil,
                                "norge" => nil,
                                "norsk" => nil,
                                "norwegian" => nil,
                                "sweden" => nil,
                                "sverige" => nil,
                                "svensk" => nil,
                                "swedish" => nil,
                                "denmark" => nil,
                                "danmark" => nil,
                                "dansk" => nil,
                                "danish" => nil,
                                "finland" => nil,
                                "suomi" => nil,
                                "finska" => nil,
                                "finnish" => nil,
                                "iceland" => nil,
                                "island" => nil,
                                "icelandic" => nil,
                                "united kingdom" => nil,
                                "england" => nil,
                                "great britain" => nil,
                                "britain" => nil,
                                "scotland" => nil,
                                "wales" => nil,
                                "germany" => nil,
                                "deutschland" => nil,
                                "france" => nil,
                                "italy" => nil,
                                "italia" => nil,
                                "spain" => nil,
                                "españa" => nil,
                                "netherlands" => nil,
                                "holland" => nil,
                                "switzerland" => nil,
                                "austria" => nil,
                                "belgium" => nil,
                                "portugal" => nil,
                                "poland" => nil,
                                "polska" => nil,
                                "czech republic" => nil,
                                "czechia" => nil,
                                "hungary" => nil,
                                "romania" => nil,
                                "greece" => nil,
                                "russia" => nil,
                                "ukraine" => nil,
                                "ireland" => nil,
                                "luxembourg" => nil,
                                "estonia" => nil,
                                "latvia" => nil,
                                "lithuania" => nil,
                                "croatia" => nil,
                                "serbia" => nil,
                                "slovakia" => nil,
                                "slovenia" => nil,
                                "bulgaria" => nil,
                                "albania" => nil,
                                "north macedonia" => nil,
                                "macedonia" => nil,
                                "bosnia" => nil,
                                "montenegro" => nil,
                                "cyprus" => nil,
                                "malta" => nil,
                                "liechtenstein" => nil,
                                "monaco" => nil,
                                "moldova" => nil,
                                "united states" => nil,
                                "america" => nil,
                                "canada" => nil,
                                "mexico" => nil,
                                "brazil" => nil,
                                "argentina" => nil,
                                "chile" => nil,
                                "colombia" => nil,
                                "peru" => nil,
                                "venezuela" => nil,
                                "ecuador" => nil,
                                "costa rica" => nil,
                                "panama" => nil,
                                "australia" => nil,
                                "new zealand" => nil,
                                "japan" => nil,
                                "china" => nil,
                                "india" => nil,
                                "south korea" => nil,
                                "korea" => nil,
                                "singapore" => nil,
                                "hong kong" => nil,
                                "taiwan" => nil,
                                "indonesia" => nil,
                                "malaysia" => nil,
                                "thailand" => nil,
                                "vietnam" => nil,
                                "philippines" => nil,
                                "israel" => nil,
                                "turkey" => nil,
                                "south africa" => nil,
                                "egypt" => nil,
                                "nigeria" => nil,
                                "kenya" => nil,
                                "ghana" => nil,
                                "ethiopia" => nil,
                                "united arab emirates" => nil
                              }),
                              &(byte_size(&1) >= 4)
                            )

  defp fuzzy_match_country(key) when byte_size(key) < 4, do: nil

  defp fuzzy_match_country(key) do
    {best_code, best_score} =
      Enum.reduce(@fuzzy_country_candidates, {nil, 0.0}, fn name,
                                                            {best_code,
                                                             best_score} ->
        score = String.jaro_distance(key, name)

        if score > best_score,
          do: {Map.get(@country_lookup, name), score},
          else: {best_code, best_score}
      end)

    if best_score >= 0.88 do
      Ysc.Logging.info("Fuzzy-matched country name",
        input: key,
        matched_code: best_code,
        score: Float.round(best_score, 3)
      )

      best_code
    else
      nil
    end
  end

  defp map_account_status("approved"), do: "active"
  defp map_account_status(_), do: "pending_approval"

  defp map_role("admin"), do: "admin"
  defp map_role(_), do: "member"

  defp load_applications(applications_data, user_map) do
    Enum.reduce_while(applications_data, {:ok, :done}, fn row, {:ok, _} ->
      email = row["email"]

      user_id =
        user_map[row["wp_user_id"]] || (email && get_user_id_by_email(email))

      if user_id && row["has_submitted_application"] do
        birth_date = parse_date(row["birth_date"])
        submitted_dt = parse_datetime(row["submitted_date"])

        attrs = %{
          user_id: user_id,
          membership_type: (row["membership_type"] || "single") |> to_string(),
          birth_date: birth_date,
          address: row["address"] || row["Address"],
          city: row["city"] || row["City"],
          region: row["region"] || row["State"],
          postal_code: row["postal_code"] || row["Zip code"],
          country: normalize_country(row["country"] || row["Country"]),
          citizenship: normalize_country(row["citizenship"]),
          most_connected_nordic_country:
            normalize_country(
              row["most_connected_nordic_country"] ||
                row["nordic_country_connected"]
            ),
          place_of_birth: normalize_country(row["place_of_birth"]),
          occupation: row["occupation"],
          link_to_scandinavia: row["link_to_scandinavia"],
          lived_in_scandinavia: row["lived_in_scandinavia"],
          spoken_languages: row["spoken_languages"],
          hear_about_the_club: row["hear_about_the_club"],
          agreed_to_bylaws: row["agreed_to_bylaws"] || false,
          agreed_to_bylaws_at: (row["agreed_to_bylaws"] && submitted_dt) || nil,
          membership_eligibility: row["membership_eligibility"] || [],
          started: submitted_dt,
          completed: submitted_dt
        }

        existing = Repo.get_by(SignupApplication, user_id: user_id)

        result =
          if existing do
            existing
            |> SignupApplication.migration_changeset(attrs)
            |> backdate_timestamp(row["submitted_date"])
            |> Repo.update()
          else
            %SignupApplication{}
            |> SignupApplication.migration_changeset(attrs)
            |> backdate_timestamp(row["submitted_date"])
            |> Repo.insert()
          end

        case result do
          {:ok, _} ->
            # Use the application's address data to fill in the user's billing
            # address — this is often the most complete source since the form
            # required it at submission time.
            upsert_address(user_id, row)
            {:cont, {:ok, :done}}

          {:error, cs} ->
            Ysc.Logging.warning("Failed to insert application",
              user_id: user_id,
              errors: inspect(cs.errors)
            )

            {:cont, {:ok, :done}}
        end
      else
        {:cont, {:ok, :done}}
      end
    end)
  end

  defp get_user_id_by_email(email) do
    case Ysc.Accounts.get_user_by_email(email) do
      %User{id: id} -> id
      nil -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} ->
        d

      _ ->
        case Timex.parse(str, "{M}/{D}/{YYYY}") do
          {:ok, dt} -> DateTime.to_date(dt)
          _ -> nil
        end
    end
  end

  defp parse_date(_), do: nil

  defp load_media(media_dir, uploader) do
    if is_nil(uploader) do
      Ysc.Logging.warning("No uploader user for media; skipping media load")
      {:ok, %{}}
    else
      subdirs =
        media_dir
        |> File.ls!()
        |> Enum.filter(fn name ->
          full = Path.join(media_dir, name)
          File.dir?(full) and name != "." and name != ".."
        end)

      Enum.reduce_while(subdirs, {:ok, %{}}, fn att_id, {:ok, acc} ->
        subdir = Path.join(media_dir, att_id)
        meta_path = Path.join(subdir, "meta.json")

        image_file =
          subdir
          |> File.ls!()
          |> Enum.find(
            &(String.downcase(Path.extname(&1)) in [
                ".jpg",
                ".jpeg",
                ".png",
                ".gif",
                ".webp"
              ])
          )

        file_path = image_file && Path.join(subdir, image_file)

        if is_nil(file_path) or not File.exists?(file_path) do
          {:cont, {:ok, acc}}
        else
          meta =
            if File.exists?(meta_path),
              do: File.read!(meta_path) |> Jason.decode!(),
              else: %{}

          # Idempotent: use existing Image if we already loaded this attachment
          existing =
            Repo.one(
              from i in Image,
                where:
                  fragment("(upload_data->>'wp_attachment_id') = ?", ^att_id)
            )

          if existing do
            {:cont, {:ok, Map.put(acc, att_id, existing)}}
          else
            key = "migration/#{att_id}/#{Path.basename(file_path)}"

            case Media.upload_file_to_s3(file_path, key) do
              %{body: %{location: location}} when is_binary(location) ->
                attrs = %{
                  raw_image_path: URI.encode(location),
                  user_id: uploader.id,
                  title: meta["title"],
                  alt_text: meta["alt_text"],
                  upload_data: %{
                    "wp_attachment_id" => att_id,
                    "created" => meta["created"]
                  }
                }

                changeset =
                  %Image{}
                  |> Image.add_image_changeset(attrs)
                  |> backdate_timestamp(meta["created"])

                case Repo.insert(changeset) do
                  {:ok, img} ->
                    # Kick off image processing to generate optimized/thumbnail
                    ImageProcessor.new(%{id: img.id}) |> Oban.insert()
                    {:cont, {:ok, Map.put(acc, att_id, img)}}

                  {:error, _} ->
                    {:cont, {:ok, acc}}
                end

              _ ->
                {:cont, {:ok, acc}}
            end
          end
        end
      end)
    end
  end

  defp load_posts(posts_data, user_map, image_map) do
    author_fallback =
      Repo.one(from u in User, where: u.role == ^:admin, limit: 1) ||
        Repo.one(User)

    # Build url_map: wp_attachment_id → new S3 URL, for HTML transformation
    url_map =
      Map.new(image_map, fn {att_id, img} -> {att_id, img.raw_image_path} end)

    Enum.reduce_while(posts_data, {:ok, :done}, fn row, {:ok, _} ->
      author_id =
        user_map[row["wp_author_id"]] || (author_fallback && author_fallback.id)

      if is_nil(author_id) do
        {:cont, {:ok, :done}}
      else
        featured_att_id = get_in(row, ["featured_image", "wp_attachment_id"])

        image_id =
          featured_att_id &&
            (image_map_image_id(image_map, featured_att_id) ||
               db_image_id_for_wp_attachment(featured_att_id))

        url_name = row["post_name"] || slugify(row["title"])
        published_on = parse_datetime(row["post_date"])

        raw_body = HtmlTransformer.wp_to_trix(row["post_content"], url_map)

        rendered_body =
          HtmlSanitizeEx.Scrubber.scrub(raw_body, Ysc.TrixScrubber)

        preview_text = generate_preview_text(rendered_body)

        attrs = %{
          user_id: author_id,
          state: "published",
          title: row["title"],
          url_name: url_name,
          raw_body: raw_body,
          rendered_body: rendered_body,
          preview_text: preview_text,
          published_on: published_on,
          image_id: image_id
        }

        existing = Repo.get_by(Post, url_name: url_name)

        result =
          if existing do
            existing
            |> Post.update_post_changeset(attrs, validate_url_name: false)
            |> backdate_timestamp(row["post_date"])
            |> Repo.update()
          else
            case %Post{}
                 |> Post.new_post_changeset(attrs, validate_url_name: false)
                 |> backdate_timestamp(row["post_date"])
                 |> Repo.insert() do
              {:error, cs} when is_list(cs.errors) ->
                if Keyword.get(cs.errors, :url_name) do
                  attrs =
                    Map.put(
                      attrs,
                      :url_name,
                      url_name <> "-" <> row["wp_post_id"]
                    )

                  %Post{}
                  |> Post.new_post_changeset(attrs, validate_url_name: false)
                  |> backdate_timestamp(row["post_date"])
                  |> Repo.insert()
                else
                  {:error, cs}
                end

              other ->
                other
            end
          end

        case result do
          {:ok, _} ->
            {:cont, {:ok, :done}}

          {:error, cs} ->
            Ysc.Logging.warning("Failed to insert post",
              url_name: url_name,
              errors: inspect(cs.errors)
            )

            {:cont, {:ok, :done}}
        end
      end
    end)
  end

  # Sets inserted_at (and updated_at) to the original WP upload datetime so
  # the Image record reflects when the file was actually added to WordPress,
  # not when the migration ran. Falls through unchanged if the date is absent
  # or unparseable.
  defp backdate_timestamp(changeset, nil), do: changeset
  defp backdate_timestamp(changeset, ""), do: changeset

  defp backdate_timestamp(changeset, created) when is_binary(created) do
    case DateTime.from_iso8601(created) do
      {:ok, dt, _} ->
        changeset
        |> Ecto.Changeset.force_change(
          :inserted_at,
          DateTime.truncate(dt, :second)
        )
        |> Ecto.Changeset.force_change(
          :updated_at,
          DateTime.truncate(dt, :second)
        )

      {:error, _} ->
        case NaiveDateTime.from_iso8601(created) do
          {:ok, ndt} ->
            dt =
              DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.truncate(:second)

            changeset
            |> Ecto.Changeset.force_change(:inserted_at, dt)
            |> Ecto.Changeset.force_change(:updated_at, dt)

          {:error, _} ->
            changeset
        end
    end
  end

  # Generates a plain-text preview from scrubbed HTML body.
  # Strips all remaining tags, collapses whitespace, and trims to 200 characters.
  defp generate_preview_text(nil), do: nil
  defp generate_preview_text(""), do: nil

  defp generate_preview_text(html) do
    text =
      html
      |> HtmlSanitizeEx.strip_tags()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    if text == "", do: nil, else: String.slice(text, 0, 200)
  end

  # Returns the new Image id from the in-memory image_map (populated this run).
  defp image_map_image_id(image_map, att_id) do
    case image_map[att_id] do
      %Image{id: id} -> id
      _ -> nil
    end
  end

  # Fallback DB lookup for the Image created in a previous migration run.
  # Used when --no-upload-media is passed or when media was loaded separately.
  defp db_image_id_for_wp_attachment(att_id) do
    Repo.one(
      from i in Image,
        where: fragment("(upload_data->>'wp_attachment_id') = ?", ^att_id),
        select: i.id,
        limit: 1
    )
  end

  defp slugify(s) when is_binary(s),
    do:
      s
      |> String.downcase()
      |> String.replace(~r/[^\w\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.slice(0, 150)

  defp slugify(_), do: "post"

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    str = String.trim(str)

    cond do
      # Already a full ISO 8601 datetime with T separator (from normalize_datetime)
      String.contains?(str, "T") ->
        case NaiveDateTime.from_iso8601(str) do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end

      # Date-only string "YYYY-MM-DD"
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, str) ->
        case NaiveDateTime.from_iso8601(str <> "T00:00:00") do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp parse_datetime(_), do: nil

  defp load_stripe(stripe_data, user_map) do
    for row <- stripe_data do
      user_id = user_map[row["wp_user_id"]]
      cus_id = row["stripe_customer_id"]
      pm_id = row["stripe_payment_method_id"]

      if user_id && cus_id && cus_id != "" do
        user = Repo.get!(User, user_id)
        ensure_stripe_customer(user, cus_id)

        # Payment methods are environment-specific and cannot be migrated
        # cross-environment (prod → sandbox). Only attempt when the PM ID
        # actually exists in the connected Stripe account.
        if pm_id && pm_id != "" do
          user = Repo.get!(User, user_id)

          case Stripe.PaymentMethod.retrieve(pm_id) do
            {:ok, stripe_pm} ->
              case Payments.upsert_and_set_default_payment_method_from_stripe(
                     user,
                     stripe_pm
                   ) do
                {:ok, _} ->
                  :ok

                {:error, reason} ->
                  Ysc.Logging.warning("Failed to set default payment method",
                    user_id: user_id,
                    stripe_payment_method_id: pm_id,
                    error: inspect(reason)
                  )
              end

            {:error, %Stripe.Error{code: :resource_missing}} ->
              Ysc.Logging.info(
                "Stripe payment method not found in this environment, skipping",
                stripe_payment_method_id: pm_id
              )

            {:error, reason} ->
              Ysc.Logging.warning("Could not retrieve Stripe payment method",
                stripe_payment_method_id: pm_id,
                error: inspect(reason)
              )
          end
        end
      end
    end

    :ok
  end

  # Ensures the user has a valid Stripe customer in the connected Stripe account.
  #
  # If the WP customer ID exists in the current Stripe environment (production
  # loading into production), it is reused. If the ID belongs to a different
  # environment (e.g. loading a production backup into a sandbox/dev Stripe
  # account), the lookup will return a :resource_missing error and we create a
  # fresh Stripe customer instead, overwriting the stale production ID.
  defp ensure_stripe_customer(user, wp_cus_id) do
    case Stripe.Customer.retrieve(wp_cus_id) do
      {:ok, _customer} ->
        if user.stripe_id != wp_cus_id do
          user
          |> User.update_user_changeset(%{stripe_id: wp_cus_id})
          |> Repo.update()
        end

      {:error, %Stripe.Error{code: :resource_missing}} ->
        if is_nil(user.stripe_id) do
          case Customers.create_stripe_customer(user) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Ysc.Logging.warning("Failed to create Stripe customer",
                user_id: user.id,
                error: inspect(reason)
              )
          end
        end

      {:error, reason} ->
        Ysc.Logging.warning("Could not verify Stripe customer",
          user_id: user.id,
          stripe_customer_id: wp_cus_id,
          error: inspect(reason)
        )
    end
  end

  defp load_subscriptions(users_data, user_map, create_stripe_subscriptions) do
    for row <- users_data do
      user_id = user_map[row["wp_user_id"]]

      if user_id && active_membership?(row) do
        renewal_dt =
          parse_subscription_datetime(
            row["sub_next_payment_date"] || row["wcm_end_date"]
          )

        start_dt =
          parse_subscription_datetime(
            row["sub_original_start_date"] || row["sub_start_date"] ||
              row["wcm_start_date"]
          )

        if is_nil(renewal_dt) do
          Ysc.Logging.warning("Skipping subscription for user: no renewal date",
            wp_user_id: row["wp_user_id"]
          )
        else
          if create_stripe_subscriptions do
            load_subscription_via_stripe(row, user_id, renewal_dt, start_dt)
          else
            load_subscription_locally(row, user_id, renewal_dt, start_dt)
          end
        end
      end
    end

    :ok
  end

  defp load_subscription_locally(_row, user_id, renewal_dt, start_dt) do
    migrated_stripe_id = "migrated_#{user_id}"

    existing = Subscriptions.get_subscription_by_stripe_id(migrated_stripe_id)

    attrs = %{
      user_id: user_id,
      name: "Membership Subscription",
      stripe_id: migrated_stripe_id,
      stripe_status: "active",
      current_period_end: renewal_dt,
      start_date: start_dt || renewal_dt
    }

    if existing do
      existing
      |> Subscription.changeset(attrs)
      |> Repo.update()
    else
      Subscriptions.create_subscription(attrs)
    end
  end

  defp load_subscription_via_stripe(row, user_id, renewal_dt, start_dt) do
    user = Ysc.Accounts.get_user!(user_id)

    unless user.stripe_id do
      Ysc.Logging.warning(
        "Skipping Stripe subscription: user has no stripe_id (ensure_stripe_customer may have failed)",
        user_id: user_id
      )
    else
      membership_type =
        row["membership_type"] || row["sub_product_name"] || "single"

      price_id = resolve_stripe_price_id(membership_type)

      unless price_id do
        Ysc.Logging.warning(
          "Skipping Stripe subscription: no configured Stripe price ID for membership type",
          user_id: user_id,
          membership_type: membership_type
        )
      else
        trial_end = DateTime.to_unix(renewal_dt)

        migrated_stripe_id = "migrated_#{user_id}"

        existing =
          Subscriptions.get_subscription_by_stripe_id(migrated_stripe_id)

        if existing && existing.stripe_id != migrated_stripe_id do
          Ysc.Logging.info(
            "Stripe subscription already exists for user, skipping",
            user_id: user_id,
            stripe_subscription_id: existing.stripe_id
          )
        else
          Ysc.Logging.info("Creating Stripe subscription for migrated user",
            user_id: user_id,
            stripe_customer_id: user.stripe_id,
            price_id: price_id,
            trial_end: trial_end
          )

          case Stripe.Subscription.create(%{
                 customer: user.stripe_id,
                 items: [%{price: price_id}],
                 trial_end: trial_end,
                 trial_settings: %{
                   end_behavior: %{missing_payment_method: "pause"}
                 }
               }) do
            {:ok, stripe_sub} ->
              attrs = %{
                user_id: user_id,
                name: "Membership Subscription",
                stripe_id: stripe_sub.id,
                stripe_status: stripe_sub.status,
                current_period_end: renewal_dt,
                start_date: start_dt || renewal_dt
              }

              if existing do
                existing
                |> Subscription.changeset(attrs)
                |> Repo.update()
              else
                Subscriptions.create_subscription(attrs)
              end

            {:error, %Stripe.Error{} = err} ->
              Ysc.Logging.warning("Failed to create Stripe subscription",
                user_id: user_id,
                stripe_customer_id: user.stripe_id,
                error: err.message
              )
          end
        end
      end
    end
  end

  defp resolve_stripe_price_id(membership_type) do
    plan_id =
      cond do
        membership_type in ["family", "Family", "wc-family"] -> :family
        true -> :single
      end

    plans = Application.get_env(:ysc, :membership_plans, [])

    case Enum.find(plans, &(&1.id == plan_id)) do
      %{stripe_price_id: id} when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  defp active_membership?(row) do
    sub = row["sub_status"]
    wcm = row["wcm_status"]

    (is_binary(sub) and sub in ["wc-active", "wc-on-hold"]) or
      (is_binary(wcm) and wcm == "wcm-active")
  end

  defp parse_subscription_datetime(nil), do: nil
  defp parse_subscription_datetime(""), do: nil

  defp parse_subscription_datetime(str) when is_binary(str) do
    str = String.trim(str)

    normalized =
      if String.contains?(str, " "),
        do: String.replace(str, " ", "T"),
        else: str

    case NaiveDateTime.from_iso8601(normalized) do
      {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
      _ -> nil
    end
  end

  defp parse_subscription_datetime(_), do: nil

  defp load_bookings(bookings_data, user_map) do
    for row <- bookings_data do
      wp_user_id = row["wp_customer_user_id"]
      user_id = wp_user_id && user_map[wp_user_id]

      if is_nil(user_id) do
        Ysc.Logging.warning(
          "Skipping WP booking: no migrated user for wp_customer_user_id",
          wp_booking_id: row["wp_booking_id"],
          wp_customer_user_id: wp_user_id
        )
      else
        load_one_booking(row, user_id)
      end
    end

    :ok
  end

  defp load_one_booking(row, user_id) do
    room_names = Enum.map(row["rooms"] || [], & &1["room_name"])

    room_structs =
      Enum.reduce_while(room_names, {:ok, []}, fn name, {:ok, acc} ->
        case Repo.get_by(Room, name: name, property: :tahoe) do
          nil ->
            Ysc.Logging.warning("Skipping room: no Room found for name",
              room_name: name,
              wp_booking_id: row["wp_booking_id"]
            )

            {:cont, {:ok, acc}}

          room ->
            {:cont, {:ok, [room | acc]}}
        end
      end)

    room_structs =
      case room_structs do
        {:ok, list} -> Enum.reverse(list)
        _ -> []
      end

    if room_structs == [] do
      Ysc.Logging.warning("Skipping WP booking: no rooms resolved",
        wp_booking_id: row["wp_booking_id"]
      )

      :ok
    else
      case parse_booking_date(row["checkin_date"]) do
        nil ->
          Ysc.Logging.warning("Skipping WP booking: invalid checkin_date",
            wp_booking_id: row["wp_booking_id"],
            checkin_date: row["checkin_date"]
          )

          :ok

        checkin_date ->
          case parse_booking_date(row["checkout_date"]) do
            nil ->
              Ysc.Logging.warning("Skipping WP booking: invalid checkout_date",
                wp_booking_id: row["wp_booking_id"],
                checkout_date: row["checkout_date"]
              )

              :ok

            checkout_date ->
              ref_id = "MIG-WP-#{row["wp_booking_id"]}"

              if Bookings.get_booking_by_reference_id(ref_id) do
                :ok
              else
                total_price = parse_booking_money(row["total_price"])

                attrs = %{
                  reference_id: ref_id,
                  checkin_date: checkin_date,
                  checkout_date: checkout_date,
                  guests_count: row["guests_count"] || 0,
                  children_count: row["children_count"] || 0,
                  property: :tahoe,
                  booking_mode: :room,
                  status: :complete,
                  total_price: total_price,
                  user_id: user_id
                }

                case Booking.changeset(%Booking{}, attrs, rooms: room_structs)
                     |> Repo.insert() do
                  {:ok, booking} ->
                    %BookingGuest{}
                    |> BookingGuest.changeset(%{
                      booking_id: booking.id,
                      first_name: row["guest_first_name"] || "Guest",
                      last_name: row["guest_last_name"] || "Guest",
                      is_booking_user: true,
                      order_index: 0
                    })
                    |> Repo.insert()

                    :ok

                  {:error, changeset} ->
                    Ysc.Logging.warning("Failed to insert migrated booking",
                      wp_booking_id: row["wp_booking_id"],
                      errors: inspect(changeset.errors)
                    )

                    :ok
                end
              end
          end
      end
    end
  end

  defp parse_booking_date(nil), do: nil
  defp parse_booking_date(""), do: nil

  defp parse_booking_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_booking_date(_), do: nil

  defp parse_booking_money(nil), do: Money.new(0, :USD)
  defp parse_booking_money(""), do: Money.new(0, :USD)

  defp parse_booking_money(v) when is_binary(v) do
    case Decimal.parse(v) do
      {decimal, _} -> Money.new(:USD, decimal)
      :error -> Money.new(0, :USD)
    end
  end

  defp parse_booking_money(_), do: Money.new(0, :USD)
end
