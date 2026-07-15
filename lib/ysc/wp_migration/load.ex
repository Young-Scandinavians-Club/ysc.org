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
  alias YscWeb.Workers.ImageProcessor
  alias Ysc.WpMigration.HtmlTransformer
  alias Ysc.WpMigration.FamilyMembers, as: WpFamilyMembers
  alias Ysc.WpMigration.BookingImport
  alias Ysc.WpMigration.MembershipPlan
  alias Ysc.WpMigration.StripeImport
  alias Ysc.WpMigration.UserNames
  alias Ysc.WpMigration.IgnoredAccounts
  alias Ysc.Newsletter

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
  - :only_emails - a single email string or list of email strings; when provided,
                   only the matching users (and their associated applications, stripe
                   data, and bookings) are loaded. Useful for targeted test runs.
  """
  def run(opts \\ []) do
    export_dir = opts[:export_dir]
    dry_run = opts[:dry_run] || false
    upload_media = Keyword.get(opts, :upload_media, true)
    create_stripe_subscriptions = opts[:create_stripe_subscriptions] || false

    only_emails = normalize_only_emails_option(opts[:only_emails])

    if export_dir do
      export_dir = Path.expand(export_dir)

      if File.dir?(export_dir) do
        do_run(
          export_dir,
          dry_run,
          upload_media,
          create_stripe_subscriptions,
          only_emails
        )
      else
        {:error, "Export directory not found: #{export_dir}"}
      end
    else
      {:error, "Missing :export_dir"}
    end
  end

  @doc """
  Creates real Stripe subscriptions for users who still have local `migrated_*` placeholders.

  WordPress managed memberships in the database only; this links each active migrated
  subscription to a real Stripe subscription with `trial_end` set to the DB
  `current_period_end` so members are not charged until their existing term ends.

  ## Options

  - `:dry_run` — log only, no Stripe or DB writes (default: false)
  - `:only_emails` — a single email or list of emails to limit the run
  """
  def create_migration_stripe_subscriptions(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    only_emails = normalize_only_emails_option(opts[:only_emails])
    report = StripeImport.new_report()

    Ysc.Logging.info(
      "[WP Load] Backfilling Stripe subscriptions for migrated placeholders",
      dry_run: dry_run,
      only_emails: only_emails
    )

    subs = list_migrated_subscriptions(only_emails)

    {stats, report} =
      Enum.reduce(
        subs,
        {%{created: 0, lifetime: 0, skipped: 0, failed: 0, dry_run: 0}, report},
        fn sub, {stats, report} ->
          case backfill_stripe_subscription_for_migration(sub, dry_run, report) do
            {status, updated_report} ->
              stats =
                case status do
                  :created -> %{stats | created: stats.created + 1}
                  :lifetime -> %{stats | lifetime: stats.lifetime + 1}
                  :skipped -> %{stats | skipped: stats.skipped + 1}
                  :failed -> %{stats | failed: stats.failed + 1}
                  :dry_run -> %{stats | dry_run: stats.dry_run + 1}
                end

              {stats, updated_report}
          end
        end
      )

    StripeImport.log_summary(report)

    {:ok, %{stats: stats, stripe_import_report: report}}
  end

  defp do_run(
         export_dir,
         dry_run,
         upload_media,
         create_stripe_subscriptions,
         only_emails
       ) do
    users_json = Path.join(export_dir, "users.json")
    applications_json = Path.join(export_dir, "applications.json")
    posts_json = Path.join(export_dir, "posts.json")
    stripe_json = Path.join(export_dir, "stripe_customer_lookup.json")
    bookings_json = Path.join(export_dir, "bookings.json")
    media_dir = Path.join(export_dir, "media")

    all_users_data = read_json(users_json) |> filter_by_emails(only_emails)
    ignored_wp_user_ids = IgnoredAccounts.ignored_wp_user_ids(all_users_data)
    users_data = IgnoredAccounts.reject_users(all_users_data)

    only_wp_user_ids =
      if only_emails do
        users_data
        |> Enum.map(& &1["wp_user_id"])
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()
      end

    if only_emails do
      Ysc.Logging.info(
        "[WP Load] :only_emails filter active — #{length(users_data)} matching users"
      )
    end

    applications_data =
      read_json(applications_json)
      |> filter_by_wp_user_ids(only_wp_user_ids, "wp_user_id")
      |> IgnoredAccounts.reject_by_wp_user_id(ignored_wp_user_ids, "wp_user_id")
      |> IgnoredAccounts.reject_user_rows()

    posts_data = read_json(posts_json)

    stripe_data =
      read_json(stripe_json)
      |> filter_by_wp_user_ids(only_wp_user_ids, "wp_user_id")
      |> IgnoredAccounts.reject_by_wp_user_id(ignored_wp_user_ids, "wp_user_id")

    bookings_data =
      read_json(bookings_json)
      |> filter_bookings(only_emails, only_wp_user_ids)
      |> IgnoredAccounts.reject_by_wp_user_id(
        ignored_wp_user_ids,
        "wp_customer_user_id"
      )

    if dry_run do
      Ysc.Logging.info(
        "[WP Load] DRY RUN — would load #{length(users_data)} users, " <>
          "#{length(applications_data)} applications, #{length(posts_data)} posts"
      )

      {:ok, %{}}
    else
      Ysc.Logging.info(
        "[WP Load] Starting migration load from #{export_dir} " <>
          "(#{length(users_data)} users, #{length(applications_data)} applications, " <>
          "#{length(posts_data)} posts, #{length(stripe_data)} stripe lookups, " <>
          "#{length(bookings_data)} bookings, stripe_subscriptions=#{create_stripe_subscriptions})"
      )

      Ysc.Settings.get_or_create_setting(
        "wp_migration_active",
        "migration",
        "true"
      )

      Ysc.Settings.update_setting("wp_migration_active", "true")

      Ysc.Logging.info(
        "[WP Load] Comms suppression ENABLED via site setting wp_migration_active=true"
      )

      uploader = get_migration_uploader()
      stripe_report = StripeImport.new_report()

      Ysc.Logging.info("[WP Load] Phase: Users")

      applications_by_wp_id =
        Map.new(applications_data, fn row -> {row["wp_user_id"], row} end)

      {:ok, user_map} = load_users(users_data, applications_by_wp_id)

      Ysc.Logging.info(
        "[WP Load] Phase: Users complete — #{map_size(user_map)} mapped"
      )

      Ysc.Logging.info("[WP Load] Phase: Applications")
      {:ok, _} = load_applications(applications_data, user_map, users_data)
      Ysc.Logging.info("[WP Load] Phase: Applications complete")

      {:ok, image_map, filename_map} =
        if upload_media and File.dir?(media_dir) do
          Ysc.Logging.info("[WP Load] Phase: Media upload")
          result = load_media(media_dir, uploader)
          Ysc.Logging.info("[WP Load] Phase: Media complete")
          result
        else
          Ysc.Logging.info("[WP Load] Phase: Media skipped")
          {:ok, %{}, %{}}
        end

      Ysc.Logging.info("[WP Load] Phase: Posts")
      {:ok, _} = load_posts(posts_data, user_map, image_map, filename_map)
      Ysc.Logging.info("[WP Load] Phase: Posts complete")

      stripe_report =
        if stripe_data != [] do
          Ysc.Logging.info(
            "[WP Load] Phase: Stripe customers (#{length(stripe_data)} lookups)"
          )

          report = load_stripe(stripe_data, user_map, stripe_report)
          Ysc.Logging.info("[WP Load] Phase: Stripe customers complete")
          report
        else
          stripe_report
        end

      Ysc.Logging.info(
        "[WP Load] Phase: Subscriptions (create_stripe=#{create_stripe_subscriptions})"
      )

      stripe_report =
        load_subscriptions(
          users_data,
          user_map,
          Map.new(applications_data, fn row -> {row["wp_user_id"], row} end),
          create_stripe_subscriptions,
          stripe_report
        )

      Ysc.Logging.info("[WP Load] Phase: Subscriptions complete")

      report_path = StripeImport.write_report(stripe_report, export_dir)
      StripeImport.log_summary(stripe_report)

      if StripeImport.failure_count(stripe_report) > 0 do
        Ysc.Logging.warning(
          "[WP Load] Stripe import failures written to #{report_path}"
        )
      end

      if bookings_data != [] do
        Ysc.Logging.info(
          "[WP Load] Phase: Bookings (#{length(bookings_data)} bookings)"
        )

        load_bookings(bookings_data, user_map)
        Ysc.Logging.info("[WP Load] Phase: Bookings complete")
      end

      Ysc.Logging.info("[WP Load] Migration load finished successfully")

      {:ok,
       %{
         user_map: user_map,
         image_map: image_map,
         stripe_import_report: stripe_report,
         stripe_import_failures_path: report_path
       }}
    end
  end

  defp read_json(path) do
    if File.exists?(path) do
      path |> File.read!() |> Jason.decode!()
    else
      []
    end
  end

  defp filter_by_emails(rows, nil), do: rows

  defp filter_by_emails(rows, only_emails) do
    Enum.filter(rows, fn row ->
      email = row["email"]
      is_binary(email) and MapSet.member?(only_emails, String.downcase(email))
    end)
  end

  defp normalize_only_emails_option(nil), do: nil

  defp normalize_only_emails_option(email) when is_binary(email) do
    MapSet.new([String.downcase(email)])
  end

  defp normalize_only_emails_option(emails) when is_list(emails) do
    valid = emails |> Enum.filter(&is_binary/1) |> Enum.map(&String.downcase/1)
    if valid == [], do: nil, else: MapSet.new(valid)
  end

  defp normalize_only_emails_option(_), do: nil

  defp list_migrated_subscriptions(only_emails) do
    Subscription
    |> join(:inner, [s], u in User, on: s.user_id == u.id)
    |> where([s], like(s.stripe_id, "migrated_%"))
    |> maybe_filter_user_emails(only_emails)
    |> order_by([_s, u], asc: u.email)
    |> preload([_s, u], subscription_items: [], user: u)
    |> Repo.all()
  end

  defp maybe_filter_user_emails(query, nil), do: query

  defp maybe_filter_user_emails(query, only_emails) do
    from [s, u] in query, where: u.email in ^MapSet.to_list(only_emails)
  end

  defp backfill_stripe_subscription_for_migration(
         %Subscription{} = sub,
         dry_run,
         report
       ) do
    user = sub.user
    email = user.email

    context = %{
      user_id: user.id,
      email: email,
      wp_user_id: nil,
      wp_stripe_customer_id: user.stripe_id
    }

    cond do
      is_nil(sub.current_period_end) ->
        Ysc.Logging.warning(
          "[WP Load] Skipping Stripe backfill for #{email}: no current_period_end"
        )

        {:skipped, report}

      MembershipPlan.lifetime_membership_date?(sub.current_period_end) ->
        if dry_run do
          Ysc.Logging.info(
            "[WP Load] Dry run: would award lifetime membership for #{email} " <>
              "(period_end=#{DateTime.to_iso8601(sub.current_period_end)})"
          )

          {:dry_run, report}
        else
          case award_lifetime_membership_from_migration(user, sub.start_date) do
            {:ok, _} ->
              {:lifetime, report}

            {:error, reason} ->
              Ysc.Logging.warning(
                "[WP Load] Failed to award lifetime membership for #{email}: #{inspect(reason)}"
              )

              {:failed, report}
          end
        end

      DateTime.compare(sub.current_period_end, DateTime.utc_now()) != :gt ->
        Ysc.Logging.info(
          "[WP Load] Skipping Stripe backfill for #{email}: membership period ended at #{DateTime.to_iso8601(sub.current_period_end)}"
        )

        {:skipped, report}

      dry_run ->
        membership_plan = membership_plan_from_subscription(sub)

        Ysc.Logging.info(
          "[WP Load] Dry run: would create Stripe subscription for #{email} " <>
            "(plan=#{membership_plan}, trial_end=#{DateTime.to_iso8601(sub.current_period_end)})"
        )

        {:dry_run, report}

      true ->
        case ensure_user_stripe_customer(user, context, report) do
          {:ok, user, report} ->
            case backfill_create_stripe_subscription(user, sub, report) do
              :ok -> {:created, report}
              {:skip, report} -> {:skipped, report}
              {:error, report} -> {:failed, report}
            end

          {:error, _reason, report} ->
            {:failed, report}
        end
    end
  end

  defp ensure_user_stripe_customer(
         %User{stripe_id: stripe_id} = user,
         _context,
         report
       )
       when is_binary(stripe_id) and stripe_id != "" do
    {:ok, user, report}
  end

  defp ensure_user_stripe_customer(%User{} = user, context, report) do
    case StripeImport.ensure_stripe_customer_for_user(user, context, report) do
      {:ok, user, report} -> {:ok, user, report}
      {:error, reason, report} -> {:error, reason, report}
    end
  end

  defp backfill_create_stripe_subscription(
         %User{} = user,
         %Subscription{} = sub,
         report
       ) do
    membership_plan = membership_plan_from_subscription(sub)
    auto_renew = is_nil(sub.ends_at)
    row = %{"email" => user.email, "wp_user_id" => nil}
    failures_before = StripeImport.failure_count(report)

    report =
      create_stripe_subscription_if_needed(
        row,
        user,
        sub.current_period_end,
        sub.start_date || sub.current_period_end,
        auto_renew,
        membership_plan,
        report
      )

    updated_sub =
      Repo.one(
        from s in Subscription,
          where: s.user_id == ^user.id,
          limit: 1
      )

    cond do
      updated_sub && !String.starts_with?(updated_sub.stripe_id, "migrated_") ->
        :ok

      StripeImport.failure_count(report) > failures_before ->
        {:error, report}

      true ->
        Ysc.Logging.warning(
          "[WP Load] Stripe backfill for #{user.email} did not produce a real subscription"
        )

        {:skip, report}
    end
  end

  defp membership_plan_from_subscription(%Subscription{
         subscription_items: [item | _]
       }) do
    membership_plan_from_price_id(item.stripe_price_id)
  end

  defp membership_plan_from_subscription(_), do: "single"

  defp membership_plan_from_price_id(price_id) do
    plans = Application.get_env(:ysc, :membership_plans, [])

    case Enum.find(plans, &(&1.stripe_price_id == price_id)) do
      %{id: :family} -> "family"
      %{id: :single} -> "single"
      _ -> "single"
    end
  end

  defp filter_by_wp_user_ids(rows, nil, _field), do: rows

  defp filter_by_wp_user_ids(rows, only_wp_user_ids, field) do
    Enum.filter(rows, fn row -> MapSet.member?(only_wp_user_ids, row[field]) end)
  end

  defp filter_bookings(rows, nil, _only_wp_user_ids), do: rows

  defp filter_bookings(rows, only_emails, only_wp_user_ids) do
    Enum.filter(rows, fn row ->
      guest_email = BookingImport.normalize_email(row["guest_email"])

      (guest_email && MapSet.member?(only_emails, guest_email)) ||
        MapSet.member?(only_wp_user_ids, row["wp_customer_user_id"])
    end)
  end

  defp get_migration_uploader do
    case Repo.one(from u in User, where: u.role == ^:admin, limit: 1) do
      nil -> Repo.one(from u in User, limit: 1)
      user -> user
    end
  end

  defp load_users(users_data, applications_by_wp_id) do
    user_map = %{}

    Enum.reduce_while(users_data, {:ok, user_map}, fn row, {:ok, acc} ->
      email = row["email"]

      if is_nil(email) or email == "" do
        {:cont, {:ok, acc}}
      else
        application_row = Map.get(applications_by_wp_id, row["wp_user_id"], %{})
        names = UserNames.resolve(row, application_row)

        case Ysc.Accounts.get_user_by_email(email) do
          existing when not is_nil(existing) ->
            # Idempotent: update profile from export when re-running
            update_attrs =
              %{
                "first_name" => names.first_name,
                "last_name" => names.last_name,
                "phone_number" => normalize_phone(row["phone_number"]),
                "state" => resolve_user_state(row),
                "role" => map_role(row["role"]),
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
                 |> apply_migration_user_verification(row)
                 |> backdate_timestamp(row["user_registered"])
                 |> Repo.update() do
              {:ok, user} ->
                upsert_address(user.id, row)
                subscribe_migrated_user_to_newsletter(user)
                {:cont, {:ok, Map.put(acc, row["wp_user_id"], user.id)}}

              {:error, _} ->
                upsert_address(existing.id, row)
                subscribe_migrated_user_to_newsletter(existing)
                {:cont, {:ok, Map.put(acc, row["wp_user_id"], existing.id)}}
            end

          nil ->
            attrs =
              %{
                "email" => email,
                "first_name" => names.first_name,
                "last_name" => names.last_name,
                "phone_number" => normalize_phone(row["phone_number"]),
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
              |> apply_migration_user_identity(row)
              |> backdate_timestamp(row["user_registered"])

            case Repo.insert(changeset) do
              {:ok, user} ->
                upsert_address(user.id, row)
                subscribe_migrated_user_to_newsletter(user)
                {:cont, {:ok, Map.put(acc, row["wp_user_id"], user.id)}}

              {:error, changeset} ->
                Ysc.Logging.warning(
                  "[WP Load] Failed to insert user #{email}: #{inspect(changeset.errors)}"
                )

                {:cont, {:ok, acc}}
            end
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

  defp subscribe_migrated_user_to_newsletter(%User{} = user) do
    metadata = %{
      "user_id" => user.id,
      "wp_migration" => true,
      "role" => to_string(user.role || "member"),
      "state" => to_string(user.state || "active")
    }

    case Newsletter.subscribe(user.email,
           user_id: user.id,
           first_name: user.first_name,
           last_name: user.last_name,
           source: "wp_migration",
           metadata: metadata
         ) do
      {:ok, _subscriber} ->
        :ok

      {:error, :invalid_email} ->
        :ok

      {:error, %Ecto.Changeset{} = changeset} ->
        Ysc.Logging.warning(
          "[WP Load] Failed to subscribe user #{user.id} to newsletter: #{inspect(changeset.errors)}"
        )

        :ok

      {:error, reason} ->
        Ysc.Logging.warning(
          "[WP Load] Failed to subscribe user #{user.id} to newsletter: #{inspect(reason)}"
        )

        :ok
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

    unless nil_or_empty?(address_str) or nil_or_empty?(country) do
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
          Ysc.Logging.warning(
            "[WP Load] Failed to upsert address for user #{user_id}: #{inspect(cs.errors)}"
          )
      end
    end
  end

  defp nil_or_empty?(nil), do: true
  defp nil_or_empty?(""), do: true
  defp nil_or_empty?(_), do: false

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
    trimmed = String.trim(raw)
    normalized = String.upcase(trimmed)

    cond do
      # Already a valid 2-letter code — accept as-is
      String.length(normalized) == 2 and
          Map.has_key?(@country_code_set, normalized) ->
        normalized

      true ->
        key = String.downcase(trimmed)

        case Map.get(@country_lookup, key) || fuzzy_match_country(key) do
          nil -> trimmed
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
      Ysc.Logging.info(
        "[WP Load] Fuzzy-matched country \"#{key}\" → #{best_code} (score=#{Float.round(best_score, 3)})"
      )

      best_code
    else
      nil
    end
  end

  defp apply_migration_user_identity(changeset, row) do
    changeset
    |> Ecto.Changeset.put_change(:state, resolve_user_state(row))
    |> Ecto.Changeset.put_change(:role, map_role(row["role"]))
    |> apply_migration_user_verification(row)
  end

  # registration_changeset/3 and update_user_changeset/3 do not cast these fields.
  # Pre-verified WP members should skip account-setup email verification and reach
  # post-migration onboarding (when active) instead of /account-setup.
  defp apply_migration_user_verification(changeset, row) do
    if resolve_user_state(row) == "active" do
      verified_at =
        parse_datetime(row["user_registered"]) ||
          DateTime.utc_now() |> DateTime.truncate(:second)

      changeset
      |> Ecto.Changeset.put_change(:email_verified_at, verified_at)
      |> Ecto.Changeset.put_change(:confirmed_at, verified_at)
    else
      changeset
    end
  end

  defp resolve_user_state(row) do
    case row["account_status"] do
      "approved" -> "active"
      "rejected" -> "rejected"
      _ -> if wp_member_active?(row), do: "active", else: "pending_approval"
    end
  end

  defp wp_member_active?(row) do
    row["has_active_wp_subscription"] == true or
      row["wcm_status"] == "wcm-active" or
      row["sub_status"] in ["wc-active", "wc-on-hold"]
  end

  defp map_role("admin"), do: "admin"
  defp map_role(_), do: "member"

  defp migration_review_attrs("approved", reviewed_at),
    do: %{
      review_outcome: :approved,
      reviewed_at: reviewed_at || DateTime.utc_now()
    }

  defp migration_review_attrs("rejected", reviewed_at),
    do: %{
      review_outcome: :rejected,
      reviewed_at: reviewed_at || DateTime.utc_now()
    }

  defp migration_review_attrs(_, _), do: %{}

  defp migration_reviewed_at(nil, submitted_dt), do: submitted_dt

  defp migration_reviewed_at(user_row, submitted_dt) do
    last_update_dt = parse_datetime(user_row["last_update"])

    cond do
      is_nil(last_update_dt) -> submitted_dt
      is_nil(submitted_dt) -> last_update_dt
      DateTime.compare(last_update_dt, submitted_dt) != :lt -> last_update_dt
      true -> submitted_dt
    end
  end

  defp load_applications(applications_data, user_map, users_data) do
    users_by_wp_id = Map.new(users_data, fn row -> {row["wp_user_id"], row} end)

    Enum.reduce_while(applications_data, {:ok, :done}, fn row, {:ok, _} ->
      email = row["email"]

      user_id =
        user_map[row["wp_user_id"]] || (email && get_user_id_by_email(email))

      if user_id && row["has_submitted_application"] do
        birth_date = parse_date(row["birth_date"])
        submitted_dt = parse_datetime(row["submitted_date"])
        user_row = Map.get(users_by_wp_id, row["wp_user_id"])

        attrs =
          %{
            user_id: user_id,
            membership_type:
              MembershipPlan.from_membership_type(row["membership_type"]) ||
                "single",
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
            agreed_to_bylaws_at:
              (row["agreed_to_bylaws"] && submitted_dt) || nil,
            membership_eligibility: row["membership_eligibility"] || [],
            started: submitted_dt,
            completed: submitted_dt
          }
          |> Map.merge(
            migration_review_attrs(
              user_row && user_row["account_status"],
              migration_reviewed_at(user_row, submitted_dt)
            )
          )

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
            upsert_address(user_id, row)

          {:error, cs} ->
            Ysc.Logging.warning(
              "[WP Load] Failed to insert application for user #{user_id}: #{inspect(cs.errors)}"
            )
        end
      end

      if user_id do
        case WpFamilyMembers.sync_for_user(user_id, row) do
          {:ok, stats} ->
            if stats.inserted + stats.updated > 0 do
              Ysc.Logging.info(
                "[WP Load] Synced family members for user #{user_id}",
                inserted: stats.inserted,
                updated: stats.updated,
                skipped: stats.skipped
              )
            end
        end
      end

      {:cont, {:ok, :done}}
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
      Ysc.Logging.warning(
        "[WP Load] No uploader user for media; skipping media load"
      )

      {:ok, %{}, %{}}
    else
      subdirs =
        media_dir
        |> File.ls!()
        |> Enum.filter(fn name ->
          full = Path.join(media_dir, name)
          File.dir?(full) and name != "." and name != ".."
        end)

      Enum.reduce_while(subdirs, {:ok, %{}, %{}}, fn att_id,
                                                     {:ok, img_acc, fname_acc} ->
        subdir = Path.join(media_dir, att_id)
        meta_path = Path.join(subdir, "meta.json")

        image_file = find_image_file_in_subdir(subdir)
        file_path = image_file && Path.join(subdir, image_file)

        if is_nil(file_path) or not File.exists?(file_path) do
          {:cont, {:ok, img_acc, fname_acc}}
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

          if existing &&
               not broken_migration_image_path?(existing.raw_image_path) do
            fname_acc =
              add_filename_entry(
                fname_acc,
                meta["original_filename"],
                existing.raw_image_path
              )

            {:cont, {:ok, Map.put(img_acc, att_id, existing), fname_acc}}
          else
            key = "migration/#{att_id}/#{Path.basename(file_path)}"

            case Media.upload_file_to_s3(file_path, key) do
              %{body: %{location: location}} when is_binary(location) ->
                raw_image_path = URI.encode(location)
                title = meta["title"]
                alt_text = meta["alt_text"] || title

                attrs = %{
                  raw_image_path: raw_image_path,
                  title: title,
                  alt_text: alt_text,
                  upload_data: %{
                    "wp_attachment_id" => att_id,
                    "created" => meta["created"],
                    "key" => key
                  }
                }

                result =
                  if existing do
                    attrs =
                      Map.merge(attrs, %{
                        optimized_image_path: nil,
                        thumbnail_path: nil,
                        blur_hash: nil,
                        width: nil,
                        height: nil,
                        processing_state: "unprocessed"
                      })

                    existing
                    |> Image.add_image_changeset(attrs)
                    |> Repo.update()
                  else
                    %Image{user_id: uploader.id}
                    |> Image.add_image_changeset(attrs)
                    |> backdate_timestamp(meta["created"])
                    |> Repo.insert()
                  end

                case result do
                  {:ok, img} ->
                    ImageProcessor.new(%{id: img.id}) |> Oban.insert()

                    fname_acc =
                      add_filename_entry(
                        fname_acc,
                        meta["original_filename"],
                        raw_image_path
                      )

                    {:cont, {:ok, Map.put(img_acc, att_id, img), fname_acc}}

                  {:error, changeset} ->
                    action = if existing, do: "update", else: "insert"

                    Ysc.Logging.warning(
                      "[WP Load] Failed to #{action} image for attachment #{att_id}: #{inspect(changeset.errors)}"
                    )

                    {:cont, {:ok, img_acc, fname_acc}}
                end

              other ->
                Ysc.Logging.warning(
                  "[WP Load] Failed to upload attachment #{att_id} to S3: #{inspect(other)}"
                )

                {:cont, {:ok, img_acc, fname_acc}}
            end
          end
        end
      end)
    end
  end

  @image_extensions [".jpg", ".jpeg", ".png", ".gif", ".webp"]

  @doc """
  Re-uploads migration media that were imported from macOS AppleDouble `._*` files
  and updates `raw_image_path` in place. Returns `{:ok, stats}`.
  """
  def repair_migration_media(export_dir, opts \\ []) do
    export_dir = Path.expand(export_dir)
    media_dir = Path.join(export_dir, "media")
    dry_run = Keyword.get(opts, :dry_run, false)

    unless File.dir?(media_dir) do
      {:error, "Media directory not found: #{media_dir}"}
    else
      broken =
        Repo.all(
          from i in Image,
            where:
              not is_nil(fragment("upload_data->>'wp_attachment_id'")) and
                ilike(i.raw_image_path, "%/._%")
        )

      stats = %{repaired: 0, skipped: 0, failed: 0}

      stats =
        Enum.reduce(broken, stats, fn image, acc ->
          att_id = image.upload_data["wp_attachment_id"]
          subdir = Path.join(media_dir, att_id)

          case find_image_file_in_subdir(subdir) do
            nil ->
              Ysc.Logging.warning(
                "[WP Load] Repair skipped attachment #{att_id}: no image file in #{subdir}"
              )

              %{acc | skipped: acc.skipped + 1}

            image_file ->
              file_path = Path.join(subdir, image_file)
              key = "migration/#{att_id}/#{image_file}"

              if dry_run do
                Ysc.Logging.info(
                  "[WP Load] Repair dry run attachment #{att_id}: would upload #{file_path} as #{key}"
                )

                %{acc | repaired: acc.repaired + 1}
              else
                case repair_migration_image(image, file_path, key) do
                  :ok ->
                    %{acc | repaired: acc.repaired + 1}

                  :error ->
                    %{acc | failed: acc.failed + 1}
                end
              end
          end
        end)

      {:ok, stats}
    end
  end

  defp repair_migration_image(image, file_path, key) do
    case Media.upload_file_to_s3(file_path, key) do
      %{body: %{location: location}} when is_binary(location) ->
        raw_image_path = URI.encode(location)

        upload_data =
          image.upload_data
          |> Map.put("key", key)

        changeset =
          image
          |> Image.add_image_changeset(%{
            raw_image_path: raw_image_path,
            upload_data: upload_data,
            optimized_image_path: nil,
            thumbnail_path: nil,
            blur_hash: nil,
            width: nil,
            height: nil,
            processing_state: "unprocessed"
          })

        case Repo.update(changeset) do
          {:ok, updated} ->
            ImageProcessor.new(%{id: updated.id}) |> Oban.insert()
            :ok

          {:error, changeset} ->
            Ysc.Logging.warning(
              "[WP Load] Repair failed to update image #{image.id}: #{inspect(changeset.errors)}"
            )

            :error
        end

      other ->
        Ysc.Logging.warning(
          "[WP Load] Repair failed to upload image #{image.id}: #{inspect(other)}"
        )

        :error
    end
  end

  defp broken_migration_image_path?(path) when is_binary(path),
    do: String.contains?(path, "/._")

  defp broken_migration_image_path?(_), do: false

  defp find_image_file_in_subdir(subdir) when is_binary(subdir) do
    case File.ls(subdir) do
      {:ok, names} ->
        names
        |> Enum.reject(&skip_media_filename?/1)
        |> Enum.filter(&image_extension?/1)
        |> prefer_extracted_image_file()

      {:error, _} ->
        nil
    end
  end

  defp skip_media_filename?(name) do
    name == "meta.json" or String.starts_with?(name, "._")
  end

  defp image_extension?(name) do
    String.downcase(Path.extname(name)) in @image_extensions
  end

  # Phase 1 extract writes `file.<ext>`; prefer that over other names in the folder.
  defp prefer_extracted_image_file([]), do: nil

  defp prefer_extracted_image_file(files) do
    Enum.find(files, &String.match?(&1, ~r/^file\.[^.]+$/i)) ||
      List.first(files)
  end

  # Adds a normalized-filename → url entry to fname_acc.
  # Normalizes by stripping the WP dimension suffix (e.g. "-841x1024") and
  # lowercasing, so "IMG_5613-841x1024.jpg" maps the same as "IMG_5613.jpg".
  defp add_filename_entry(acc, nil, _url), do: acc
  defp add_filename_entry(acc, "", _url), do: acc

  defp add_filename_entry(acc, original_filename, url) do
    normalized = normalize_wp_image_filename(original_filename)
    Map.put_new(acc, normalized, url)
  end

  defp normalize_wp_image_filename(filename) do
    filename
    |> String.replace(~r/-\d+x\d+(\.[^.]+)$/, "\\1")
    |> String.downcase()
  end

  defp load_posts(posts_data, user_map, image_map, filename_map) do
    author_fallback =
      Repo.one(from u in User, where: u.role == ^:admin, limit: 1) ||
        Repo.one(User)

    # Build url_map: wp_attachment_id → new S3 URL for class-based lookups,
    # merged with normalized_filename → new S3 URL for src-based fallback.
    # filename_map keys are already normalized (lowercase, no WP size suffix).
    url_map =
      image_map
      |> Map.new(fn {att_id, img} -> {att_id, img.raw_image_path} end)
      |> Map.merge(filename_map)

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

        # If no WP featured image, fall back to the first image found in the
        # post body: try by wp-image-{id} att_ids extracted at export time first,
        # then scan the transformed raw_body for the first <img src> as a last resort.
        image_id =
          image_id ||
            first_body_image_id(row["wp_attachment_ids_in_content"], image_map) ||
            first_body_image_id_from_src(raw_body)

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
            |> Ecto.Changeset.put_change(:user_id, author_id)
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
            Ysc.Logging.warning(
              "[WP Load] Failed to insert post \"#{url_name}\": #{inspect(cs.errors)}"
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
  @dialyzer {:nowarn_function, generate_preview_text: 1}
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

  # Returns the Image id for the first att_id in the list that resolves to a
  # known Image (via image_map then DB). Used as featured image fallback when
  # the WP post has no explicit thumbnail set.
  defp first_body_image_id(nil, _image_map), do: nil
  defp first_body_image_id([], _image_map), do: nil

  defp first_body_image_id([att_id | rest], image_map) do
    case image_map_image_id(image_map, att_id) ||
           db_image_id_for_wp_attachment(att_id) do
      nil -> first_body_image_id(rest, image_map)
      id -> id
    end
  end

  # Last-resort fallback: parse the transformed post body for the first <img>
  # and look up the Image record by its raw_image_path.
  @dialyzer {:nowarn_function, first_body_image_id_from_src: 1}
  defp first_body_image_id_from_src(nil), do: nil
  defp first_body_image_id_from_src(""), do: nil

  defp first_body_image_id_from_src(html) do
    src =
      html
      |> Floki.parse_fragment!()
      |> Floki.find("img")
      |> Enum.find_value(fn img ->
        case Floki.attribute(img, "src") do
          [s | _] when s != "" -> s
          _ -> nil
        end
      end)

    if src do
      Repo.one(
        from i in Image,
          where: i.raw_image_path == ^src,
          select: i.id,
          limit: 1
      )
    end
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

  defp load_stripe(stripe_data, user_map, report) do
    Enum.reduce(stripe_data, report, fn row, acc_report ->
      user_id = user_map[row["wp_user_id"]]
      cus_id = row["stripe_customer_id"]
      pm_id = row["stripe_payment_method_id"]

      if user_id && cus_id && cus_id != "" do
        user = Repo.get!(User, user_id)

        context = %{
          user_id: user_id,
          email: user.email,
          wp_user_id: row["wp_user_id"],
          wp_stripe_customer_id: cus_id
        }

        {user, acc_report} =
          case StripeImport.link_wp_stripe_customer(
                 user,
                 cus_id,
                 context,
                 acc_report
               ) do
            {:ok, linked_user, report} -> {linked_user, report}
            {:error, _reason, report} -> {user, report}
          end

        if pm_id && pm_id != "" do
          user = Repo.get!(User, user.id)

          case Ysc.Stripe.RetryHelper.stripe_retry_transient(fn ->
                 stripe_payment_method_module().retrieve(pm_id, [])
               end) do
            {:ok, stripe_pm} ->
              case Payments.upsert_and_set_default_payment_method_from_stripe(
                     user,
                     stripe_pm
                   ) do
                {:ok, _} ->
                  acc_report

                {:error, reason} ->
                  StripeImport.record_failure(
                    acc_report,
                    %{
                      category: "stripe_payment_method",
                      user_id: user_id,
                      email: user.email,
                      wp_user_id: row["wp_user_id"],
                      stripe_payment_method_id: pm_id,
                      reason: inspect(reason)
                    }
                  )
              end

            {:error, %Stripe.Error{code: :resource_missing}} ->
              Ysc.Logging.info(
                "[WP Load] Stripe PM #{pm_id} not found in this environment, skipping"
              )

              acc_report

            {:error, reason} ->
              StripeImport.record_failure(
                acc_report,
                %{
                  category: "stripe_payment_method",
                  user_id: user_id,
                  email: user.email,
                  wp_user_id: row["wp_user_id"],
                  stripe_payment_method_id: pm_id,
                  reason: format_stripe_failure_reason(reason)
                }
              )
          end
        else
          acc_report
        end
      else
        acc_report
      end
    end)
  end

  defp load_subscriptions(
         users_data,
         user_map,
         applications_by_wp_id,
         create_stripe_subscriptions,
         report
       ) do
    Enum.reduce(users_data, report, fn row, acc_report ->
      user_id = user_map[row["wp_user_id"]]

      if user_id && active_membership?(row) do
        auto_renew = should_auto_renew?(row)
        recorded_end_dt = best_end_date(row)
        membership_plan = resolve_membership_plan(row, applications_by_wp_id)

        start_dt =
          parse_subscription_datetime(
            row["sub_original_start_date"] || row["sub_start_date"] ||
              row["wcm_start_date"]
          )

        context = %{
          user_id: user_id,
          email: row["email"],
          wp_user_id: row["wp_user_id"],
          wp_stripe_customer_id: nil
        }

        cond do
          is_nil(recorded_end_dt) ->
            Ysc.Logging.warning(
              "[WP Load] Skipping subscription for wp_user #{row["wp_user_id"]} (#{row["email"]}): no renewal date found"
            )

            acc_report

          MembershipPlan.lifetime_membership_date?(recorded_end_dt) ->
            user = Repo.get!(User, user_id)

            case award_lifetime_membership_from_migration(user, start_dt) do
              {:ok, _} ->
                Ysc.Logging.info(
                  "[WP Load] Awarded lifetime membership for user #{user_id} (#{row["email"]}) " <>
                    "from far-future WP renewal date #{DateTime.to_iso8601(recorded_end_dt)}"
                )

                acc_report

              {:error, reason} ->
                Ysc.Logging.warning(
                  "[WP Load] Failed to award lifetime membership for user #{user_id} (#{row["email"]}): #{inspect(reason)}"
                )

                acc_report
            end

          true ->
            user = Repo.get!(User, user_id)

            case StripeImport.import_subscriptions_for_user(
                   user,
                   context,
                   acc_report
                 ) do
              {:ok, status, report}
              when status in [:imported, :already_linked] ->
                Ysc.Logging.info(
                  "[WP Load] Using existing Stripe subscription for user #{user_id} (#{status})"
                )

                report

              {:ok, :no_stripe_customer, report} ->
                load_subscription_fallback(
                  %{
                    row: row,
                    user_id: user_id,
                    renewal_dt: recorded_end_dt,
                    start_dt: start_dt,
                    auto_renew: auto_renew,
                    membership_plan: membership_plan,
                    context: context,
                    report: report
                  },
                  create_stripe_subscriptions
                )

              {:ok, :none_found, report} ->
                load_subscription_fallback(
                  %{
                    row: row,
                    user_id: user_id,
                    renewal_dt: recorded_end_dt,
                    start_dt: start_dt,
                    auto_renew: auto_renew,
                    membership_plan: membership_plan,
                    context: context,
                    report: report
                  },
                  create_stripe_subscriptions
                )

              {:error, _reason, report} ->
                Ysc.Logging.warning(
                  "[WP Load] Stripe subscription import failed for user #{user_id}; " <>
                    "falling back to local migrated subscription"
                )

                load_subscription_fallback(
                  %{
                    row: row,
                    user_id: user_id,
                    renewal_dt: recorded_end_dt,
                    start_dt: start_dt,
                    auto_renew: auto_renew,
                    membership_plan: membership_plan,
                    context: context,
                    report: report
                  },
                  false
                )
            end
        end
      else
        acc_report
      end
    end)
  end

  defp load_subscription_fallback(load, create_stripe_subscriptions) do
    if create_stripe_subscriptions do
      load_subscription_via_stripe(
        load.row,
        load.user_id,
        load.renewal_dt,
        load.start_dt,
        load.auto_renew,
        load.membership_plan,
        load.context,
        load.report
      )
    else
      load_subscription_locally(
        load.row,
        load.user_id,
        load.renewal_dt,
        load.start_dt,
        load.auto_renew,
        load.membership_plan
      )

      load.report
    end
  end

  defp resolve_membership_plan(user_row, applications_by_wp_id) do
    application = Map.get(applications_by_wp_id, user_row["wp_user_id"], %{})

    MembershipPlan.resolve(%{
      wcm_product_name: user_row["wcm_product_name"],
      sub_product_name: user_row["sub_product_name"],
      application_membership_type: application["membership_type"],
      user_membership_type: user_row["membership_type"]
    })
  end

  # User had an active WP subscription (including on-hold, which indicates a
  # payment hiccup but the intent to keep renewing). Users who only had a
  # WooCommerce Membership record without an underlying subscription were
  # managed manually and should not auto-renew.
  defp should_auto_renew?(row) do
    row["has_active_wp_subscription"] == true or
      (is_binary(row["sub_status"]) and
         row["sub_status"] in ["wc-active", "wc-on-hold"])
  end

  # Pick the most favorable (latest) end date for the user by comparing:
  #   1. The recorded end date from WP (sub_next_payment_date / wcm_end_date)
  #   2. The date derived from their last membership payment + 1 year
  defp best_end_date(row) do
    recorded =
      parse_subscription_datetime(
        row["sub_next_payment_date"] || row["wcm_end_date"]
      )

    payment_derived =
      case parse_subscription_datetime(row["last_membership_payment_date"]) do
        %DateTime{} = dt ->
          # Renewals are always for 1 year
          date = DateTime.to_date(dt)
          next_year = date.year + 1
          max_day = :calendar.last_day_of_the_month(next_year, date.month)
          renewed = Date.new!(next_year, date.month, min(date.day, max_day))
          DateTime.new!(renewed, ~T[00:00:00], "Etc/UTC")

        _ ->
          nil
      end

    pick_latest_datetime(recorded, payment_derived)
  end

  defp pick_latest_datetime(nil, nil), do: nil
  defp pick_latest_datetime(nil, b), do: b
  defp pick_latest_datetime(a, nil), do: a

  defp pick_latest_datetime(a, b) do
    if DateTime.compare(a, b) == :lt, do: b, else: a
  end

  defp load_subscription_locally(
         _row,
         user_id,
         renewal_dt,
         start_dt,
         auto_renew,
         membership_plan
       ) do
    migrated_stripe_id = "migrated_#{user_id}"

    existing = Subscriptions.get_subscription_by_stripe_id(migrated_stripe_id)

    expired? = DateTime.compare(renewal_dt, DateTime.utc_now()) != :gt

    attrs = %{
      user_id: user_id,
      name: "Membership Subscription",
      stripe_id: migrated_stripe_id,
      stripe_status: if(expired?, do: "canceled", else: "active"),
      current_period_end: renewal_dt,
      start_date: start_dt || renewal_dt,
      ends_at: if(auto_renew && !expired?, do: nil, else: renewal_dt)
    }

    Ysc.Logging.info(
      "[WP Load] Creating local subscription for user #{user_id}: " <>
        "plan=#{membership_plan}, auto_renew=#{auto_renew}, " <>
        "period_end=#{DateTime.to_iso8601(renewal_dt)}, expired=#{expired?}"
    )

    sub_result =
      if existing do
        existing
        |> Subscription.changeset(attrs)
        |> Repo.update()
      else
        Subscriptions.create_subscription(attrs)
      end

    case sub_result do
      {:ok, subscription} ->
        price_id = resolve_stripe_price_id(membership_plan)

        if price_id do
          create_subscription_item_for_migration(
            subscription,
            nil,
            price_id,
            membership_plan
          )
        end

        {:ok, subscription}

      error ->
        error
    end
  end

  @dialyzer {:nowarn_function, load_subscription_via_stripe: 8}
  defp load_subscription_via_stripe(
         row,
         user_id,
         renewal_dt,
         start_dt,
         auto_renew,
         membership_plan,
         context,
         report
       ) do
    user = Repo.get!(User, user_id)

    case StripeImport.ensure_stripe_customer_for_user(user, context, report) do
      {:ok, user, report} ->
        if user.stripe_id &&
             StripeImport.customer_has_importable_stripe_subscription?(
               user.stripe_id
             ) do
          case StripeImport.import_subscriptions_for_user(user, context, report) do
            {:ok, status, report}
            when status in [:imported, :already_linked] ->
              Ysc.Logging.info(
                "[WP Load] Found existing Stripe subscription for user #{user_id} before create; imported"
              )

              report

            other ->
              create_stripe_subscription_if_needed(
                row,
                user,
                renewal_dt,
                start_dt,
                auto_renew,
                membership_plan,
                elem(other, 2)
              )
          end
        else
          create_stripe_subscription_if_needed(
            row,
            user,
            renewal_dt,
            start_dt,
            auto_renew,
            membership_plan,
            report
          )
        end

      {:error, reason, report} ->
        Ysc.Logging.warning(
          "[WP Load] Skipping Stripe subscription create for user #{user_id}: #{format_stripe_failure_reason(reason)}"
        )

        load_subscription_locally(
          row,
          user_id,
          renewal_dt,
          start_dt,
          false,
          membership_plan
        )

        report
    end
  end

  defp create_stripe_subscription_if_needed(
         row,
         user,
         renewal_dt,
         start_dt,
         auto_renew,
         membership_plan,
         report
       ) do
    user_id = user.id

    if MembershipPlan.lifetime_membership_date?(renewal_dt) do
      case award_lifetime_membership_from_migration(user, start_dt) do
        {:ok, _} ->
          Ysc.Logging.info(
            "[WP Load] Awarded lifetime membership for user #{user_id} instead of creating Stripe subscription"
          )

          report

        {:error, reason} ->
          Ysc.Logging.warning(
            "[WP Load] Failed to award lifetime membership for user #{user_id}: #{inspect(reason)}"
          )

          report
      end
    else
      do_create_stripe_subscription_if_needed(
        row,
        user,
        renewal_dt,
        start_dt,
        auto_renew,
        membership_plan,
        report
      )
    end
  end

  defp do_create_stripe_subscription_if_needed(
         row,
         user,
         renewal_dt,
         start_dt,
         auto_renew,
         membership_plan,
         report
       ) do
    user_id = user.id
    price_id = resolve_stripe_price_id(membership_plan)

    if price_id do
      trial_end = stripe_trial_end_unix(renewal_dt)

      existing =
        Repo.one(
          from s in Ysc.Subscriptions.Subscription,
            where: s.user_id == ^user_id,
            limit: 1
        )

      if existing && !String.starts_with?(existing.stripe_id, "migrated_") do
        Ysc.Logging.info(
          "[WP Load] Stripe subscription already exists for user #{user_id} (sub=#{existing.stripe_id}), skipping create"
        )

        report
      else
        now_unix = DateTime.to_unix(DateTime.utc_now())

        if trial_end <= now_unix do
          Ysc.Logging.info(
            "[WP Load] Membership expired for user #{user_id}, creating local-only subscription (trial_end=#{trial_end} is in the past)"
          )

          load_subscription_locally(
            row,
            user_id,
            renewal_dt,
            start_dt,
            false,
            membership_plan
          )

          report
        else
          Ysc.Logging.info(
            "[WP Load] Creating Stripe subscription for user #{user_id}: " <>
              "plan=#{membership_plan}, customer=#{user.stripe_id}, price=#{price_id}, " <>
              "trial_end=#{trial_end}, auto_renew=#{auto_renew}"
          )

          stripe_params = %{
            customer: user.stripe_id,
            items: [%{price: price_id}],
            trial_end: trial_end,
            trial_settings: %{
              end_behavior: %{missing_payment_method: "pause"}
            },
            metadata: %{"wp_migration" => "true"}
          }

          stripe_params =
            if auto_renew do
              stripe_params
            else
              Map.put(stripe_params, :cancel_at_period_end, true)
            end

          case Ysc.Stripe.RetryHelper.stripe_retry_transient(fn ->
                 stripe_subscription_module().create(stripe_params, [])
               end) do
            {:ok, stripe_sub} ->
              attrs = %{
                user_id: user_id,
                name: "Membership Subscription",
                stripe_id: stripe_sub.id,
                stripe_status: stripe_sub.status,
                current_period_end: renewal_dt,
                start_date: start_dt || renewal_dt,
                ends_at: if(auto_renew, do: nil, else: renewal_dt)
              }

              sub_result =
                if existing do
                  existing
                  |> Subscription.changeset(attrs)
                  |> Repo.update()
                else
                  Subscriptions.create_subscription(attrs)
                end

              case sub_result do
                {:ok, subscription} ->
                  StripeImport.remove_migrated_placeholder(user_id)

                  create_subscription_item_for_migration(
                    subscription,
                    stripe_sub,
                    price_id,
                    membership_plan
                  )

                  report

                {:error, changeset} ->
                  Ysc.Logging.error(
                    "[WP Load] Local subscription persistence failed for user #{user_id} " <>
                      "(stripe_sub=#{stripe_sub.id}): #{inspect(changeset.errors)}; " <>
                      "canceling orphaned Stripe subscription"
                  )

                  Ysc.Stripe.RetryHelper.stripe_retry_transient(fn ->
                    stripe_subscription_module().cancel(stripe_sub.id, [])
                  end)

                  StripeImport.record_failure(
                    report,
                    %{
                      category: "stripe_subscription_create",
                      user_id: user_id,
                      email: row["email"],
                      wp_user_id: row["wp_user_id"],
                      stripe_customer_id: user.stripe_id,
                      reason: inspect(changeset.errors)
                    }
                  )
              end

            {:error, %Stripe.Error{} = err} ->
              report =
                StripeImport.record_failure(
                  report,
                  %{
                    category: "stripe_subscription_create",
                    user_id: user_id,
                    email: row["email"],
                    wp_user_id: row["wp_user_id"],
                    stripe_customer_id: user.stripe_id,
                    reason: format_stripe_failure_reason(err)
                  }
                )

              Ysc.Logging.warning(
                "[WP Load] Failed to create Stripe subscription for user #{user_id} (customer=#{user.stripe_id}): #{err.message}"
              )

              load_subscription_locally(
                row,
                user_id,
                renewal_dt,
                start_dt,
                false,
                membership_plan
              )

              report

            {:error, other} ->
              report =
                StripeImport.record_failure(
                  report,
                  %{
                    category: "stripe_subscription_create",
                    user_id: user_id,
                    email: row["email"],
                    wp_user_id: row["wp_user_id"],
                    stripe_customer_id: user.stripe_id,
                    reason: inspect(other)
                  }
                )

              Ysc.Logging.warning(
                "[WP Load] Failed to create Stripe subscription for user #{user_id} (customer=#{user.stripe_id}): #{inspect(other)}"
              )

              load_subscription_locally(
                row,
                user_id,
                renewal_dt,
                start_dt,
                false,
                membership_plan
              )

              report
          end
        end
      end
    else
      Ysc.Logging.warning(
        "[WP Load] Skipping Stripe subscription for user #{user_id}: no configured price ID for membership_plan=#{membership_plan}"
      )

      load_subscription_locally(
        row,
        user_id,
        renewal_dt,
        start_dt,
        auto_renew,
        membership_plan
      )

      report
    end
  end

  defp award_lifetime_membership_from_migration(%User{} = user, awarded_at) do
    awarded_at =
      case awarded_at do
        %DateTime{} = dt -> DateTime.truncate(dt, :second)
        _ -> DateTime.utc_now() |> DateTime.truncate(:second)
      end

    active_sub =
      Repo.one(
        from s in Subscription,
          where: s.user_id == ^user.id,
          limit: 1
      )

    if active_sub && Subscriptions.active?(active_sub) &&
         !String.starts_with?(active_sub.stripe_id, "migrated_") do
      case Subscriptions.cancel(active_sub) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Ysc.Logging.warning(
            "[WP Load] Failed to cancel Stripe subscription for user #{user.id} when awarding lifetime: #{inspect(reason)}"
          )
      end
    end

    StripeImport.remove_migrated_placeholder(user.id)

    if is_nil(user.lifetime_membership_awarded_at) do
      user
      |> User.update_user_changeset(%{
        lifetime_membership_awarded_at: awarded_at
      })
      |> Repo.update()
      |> tap(fn
        {:ok, updated} ->
          Ysc.Accounts.MembershipCache.invalidate_user(updated.id)

        _ ->
          :ok
      end)
    else
      {:ok, user}
    end
  end

  defp format_stripe_failure_reason(%Stripe.Error{} = error) do
    parts =
      [
        error.code && "code=#{error.code}",
        error.message && "message=#{error.message}"
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, ", ")
  end

  defp format_stripe_failure_reason(reason) when is_binary(reason), do: reason
  defp format_stripe_failure_reason(reason), do: inspect(reason)

  # Stripe allows at most 730 days (two years) of trial.
  defp stripe_trial_end_unix(%DateTime{} = renewal_dt) do
    renewal_unix = DateTime.to_unix(renewal_dt)

    max_unix =
      DateTime.utc_now()
      |> DateTime.add(730 - 7, :day)
      |> DateTime.to_unix()

    capped = min(renewal_unix, max_unix)

    if capped != renewal_unix do
      Ysc.Logging.info(
        "[WP Load] Capped Stripe trial_end from #{renewal_unix} to #{capped} (Stripe two-year trial limit)"
      )
    end

    capped
  end

  defp resolve_stripe_price_id(membership_plan) do
    plan_id =
      case membership_plan do
        "family" -> :family
        _ -> :single
      end

    plans = Application.get_env(:ysc, :membership_plans, [])

    case Enum.find(plans, &(&1.id == plan_id)) do
      %{stripe_price_id: id} when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  defp create_subscription_item_for_migration(
         subscription,
         stripe_sub,
         price_id,
         membership_plan
       ) do
    plan_id =
      case membership_plan do
        "family" -> :family
        _ -> :single
      end

    plans = Application.get_env(:ysc, :membership_plans, [])
    plan = Enum.find(plans, &(&1.id == plan_id))

    stripe_item_id =
      case stripe_sub do
        %{items: %{data: [%{id: id} | _]}} -> id
        _ -> "migrated_item_#{subscription.id}"
      end

    stripe_product_id =
      case stripe_sub do
        %{items: %{data: [%{price: %{product: prod}} | _]}} -> prod
        _ -> "migrated_product_#{plan_id}"
      end

    existing =
      Repo.get_by(Ysc.Subscriptions.SubscriptionItem,
        subscription_id: subscription.id
      )

    attrs = %{
      stripe_id: stripe_item_id,
      stripe_product_id: stripe_product_id,
      stripe_price_id: price_id,
      quantity: 1,
      subscription_id: subscription.id
    }

    result =
      case existing do
        nil ->
          %Ysc.Subscriptions.SubscriptionItem{}
          |> Ysc.Subscriptions.SubscriptionItem.changeset(attrs)
          |> Repo.insert()

        item ->
          item
          |> Ysc.Subscriptions.SubscriptionItem.changeset(attrs)
          |> Repo.update()
      end

    case result do
      {:ok, _} ->
        Ysc.Accounts.MembershipCache.invalidate_user(subscription.user_id)

        Ysc.Logging.info(
          "[WP Load] Created subscription_item for user #{subscription.user_id}: plan=#{plan && plan.name}, price=#{price_id}"
        )

      {:error, changeset} ->
        Ysc.Logging.warning(
          "[WP Load] Failed to create subscription_item for user #{subscription.user_id}: #{inspect(changeset.errors)}"
        )
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
      user_id = BookingImport.resolve_migrated_user_id(row, user_map)

      if is_nil(user_id) do
        Ysc.Logging.warning(
          "[WP Load] Skipping booking #{row["wp_booking_id"]}: no migrated user for " <>
            "guest_email=#{inspect(row["guest_email"])} " <>
            "wp_customer_user_id=#{inspect(row["wp_customer_user_id"])}"
        )
      else
        user = Repo.get!(User, user_id)

        load_one_booking(
          row,
          user_id,
          user.first_name || "",
          user.last_name || ""
        )
      end
    end

    :ok
  end

  defp load_one_booking(row, user_id, booking_user_first, booking_user_last) do
    ref_id = "MIG-WP-#{row["wp_booking_id"]}"

    case Bookings.get_booking_by_reference_id(ref_id) do
      %Booking{} = existing ->
        fix_migrated_booking(
          existing,
          user_id,
          row,
          booking_user_first,
          booking_user_last
        )

      nil ->
        insert_migrated_booking_if_valid(
          row,
          user_id,
          booking_user_first,
          booking_user_last,
          ref_id
        )
    end
  end

  defp insert_migrated_booking_if_valid(
         row,
         user_id,
         booking_user_first,
         booking_user_last,
         ref_id
       ) do
    raw_room_names = Enum.map(row["rooms"] || [], & &1["room_name"])

    buyout? =
      Enum.any?(raw_room_names, fn name ->
        normalized = String.downcase(name || "")

        String.contains?(normalized, "buyout") or
          String.contains?(normalized, "full cabin")
      end)

    {room_structs, booking_mode} =
      if buyout? do
        {[], :buyout}
      else
        rooms =
          raw_room_names
          |> Enum.map(&normalize_wp_room_name/1)
          |> Enum.reduce([], fn name, acc ->
            case find_room_by_name(name) do
              nil ->
                Ysc.Logging.warning(
                  "[WP Load] Skipping room \"#{name}\" in booking #{row["wp_booking_id"]}: no match in DB"
                )

                acc

              room ->
                [room | acc]
            end
          end)
          |> Enum.reverse()

        {rooms, :room}
      end

    if room_structs == [] and not buyout? do
      Ysc.Logging.warning(
        "[WP Load] Skipping booking #{row["wp_booking_id"]}: no rooms resolved from #{inspect(raw_room_names)}"
      )

      :ok
    else
      case parse_booking_date(row["checkin_date"]) do
        nil ->
          Ysc.Logging.warning(
            "[WP Load] Skipping booking #{row["wp_booking_id"]}: invalid checkin_date=#{inspect(row["checkin_date"])}"
          )

          :ok

        checkin_date ->
          case parse_booking_date(row["checkout_date"]) do
            nil ->
              Ysc.Logging.warning(
                "[WP Load] Skipping booking #{row["wp_booking_id"]}: invalid checkout_date=#{inspect(row["checkout_date"])}"
              )

              :ok

            checkout_date ->
              insert_migrated_booking(
                row,
                user_id,
                booking_user_first,
                booking_user_last,
                %{
                  ref_id: ref_id,
                  checkin_date: checkin_date,
                  checkout_date: checkout_date,
                  room_structs: room_structs,
                  booking_mode: booking_mode
                }
              )
          end
      end
    end
  end

  defp insert_migrated_booking(
         row,
         user_id,
         booking_user_first,
         booking_user_last,
         parsed
       ) do
    total_price = parse_booking_money(row["total_price"])

    attrs = %{
      reference_id: parsed.ref_id,
      checkin_date: parsed.checkin_date,
      checkout_date: parsed.checkout_date,
      guests_count: row["guests_count"] || 0,
      children_count: row["children_count"] || 0,
      property: :tahoe,
      booking_mode: parsed.booking_mode,
      status: :complete,
      total_price: total_price,
      user_id: user_id
    }

    case Booking.changeset(%Booking{}, attrs,
           rooms: parsed.room_structs,
           skip_validation: true
         )
         |> Repo.insert() do
      {:ok, booking} ->
        case insert_migrated_booking_guest(
               booking,
               row,
               booking_user_first,
               booking_user_last
             ) do
          {:ok, _guest} ->
            :ok

          {:error, changeset} ->
            Ysc.Logging.warning(
              "[WP Load] Failed to insert guest for booking #{row["wp_booking_id"]}: #{inspect(changeset.errors)}"
            )

            {:error, changeset}
        end

      {:error, changeset} ->
        Ysc.Logging.warning(
          "[WP Load] Failed to insert booking #{row["wp_booking_id"]}: #{inspect(changeset.errors)}"
        )

        :ok
    end
  end

  defp fix_migrated_booking(
         existing,
         user_id,
         row,
         booking_user_first,
         booking_user_last
       ) do
    existing = Repo.preload(existing, :booking_guests)

    existing =
      if existing.user_id != user_id do
        case existing
             |> Ecto.Changeset.change(user_id: user_id)
             |> Repo.update() do
          {:ok, booking} ->
            Ysc.Logging.info(
              "[WP Load] Fixed booking member for #{booking.reference_id} (wp_booking #{row["wp_booking_id"]})"
            )

            booking

          {:error, changeset} ->
            Ysc.Logging.warning(
              "[WP Load] Failed to fix booking member for #{existing.reference_id}: #{inspect(changeset.errors)}"
            )

            existing
        end
      else
        existing
      end

    sync_migrated_booking_guest(
      existing,
      row,
      booking_user_first,
      booking_user_last
    )
  end

  defp insert_migrated_booking_guest(
         booking,
         row,
         booking_user_first,
         booking_user_last
       ) do
    guest_attrs =
      migrated_guest_attrs(row, booking_user_first, booking_user_last)

    %BookingGuest{}
    |> BookingGuest.changeset(Map.put(guest_attrs, :booking_id, booking.id))
    |> Repo.insert()
  end

  defp sync_migrated_booking_guest(
         booking,
         row,
         booking_user_first,
         booking_user_last
       ) do
    guest_attrs =
      migrated_guest_attrs(row, booking_user_first, booking_user_last)

    case booking.booking_guests do
      [] ->
        insert_migrated_booking_guest(
          booking,
          row,
          booking_user_first,
          booking_user_last
        )

      [guest] ->
        guest
        |> BookingGuest.changeset(guest_attrs)
        |> Repo.update()

      guests ->
        Enum.reduce_while(guests, {:ok, :synced}, fn guest, {:ok, _} ->
          is_user =
            BookingImport.guest_is_booking_user?(
              guest.first_name,
              guest.last_name,
              booking_user_first,
              booking_user_last
            )

          case guest
               |> BookingGuest.changeset(%{is_booking_user: is_user})
               |> Repo.update() do
            {:ok, updated} -> {:cont, {:ok, updated}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        end)
    end
    |> case do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Ysc.Logging.warning(
          "[WP Load] Failed to sync booking guest for #{booking.reference_id}: #{inspect(changeset.errors)}"
        )

        {:error, changeset}
    end
  end

  defp migrated_guest_attrs(row, booking_user_first, booking_user_last) do
    guest_first = row["guest_first_name"] || "Guest"
    guest_last = row["guest_last_name"] || "Guest"

    %{
      first_name: guest_first,
      last_name: guest_last,
      is_booking_user:
        BookingImport.guest_is_booking_user?(
          guest_first,
          guest_last,
          booking_user_first,
          booking_user_last
        ),
      order_index: 0
    }
  end

  # Strip property prefixes like "Tahoe " and normalize case so that
  # WP names like "Tahoe Room 5A" match DB names like "Room 5a".
  defp normalize_wp_room_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    if trimmed == "" do
      name
    else
      trimmed
      |> String.replace(~r/^tahoe\s+/i, "")
      |> String.trim()
      |> String.downcase()
      |> String.split(" ")
      |> Enum.map_join(" ", &String.capitalize/1)
    end
  end

  defp normalize_wp_room_name(name), do: name

  # Case-insensitive room lookup: tries exact match first, then ILIKE.
  defp find_room_by_name(name) when is_binary(name) and name != "" do
    case Repo.get_by(Room, name: name, property: :tahoe) do
      nil ->
        Repo.one(
          from r in Room,
            where:
              r.property == :tahoe and
                fragment("LOWER(?)", r.name) == ^String.downcase(name),
            limit: 1
        )

      room ->
        room
    end
  end

  defp find_room_by_name(_name), do: nil

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

  defp stripe_payment_method_module do
    Application.get_env(
      :ysc,
      :stripe_payment_method_module,
      Stripe.PaymentMethod
    )
  end

  defp stripe_subscription_module do
    Application.get_env(:ysc, :stripe_subscription_module, Stripe.Subscription)
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    user_ids = [Fixtures.ulid()]

    from(u in User,
      where: u.id in ^user_ids,
      select: {u.id, u.first_name, u.last_name}
    )
  end
end
