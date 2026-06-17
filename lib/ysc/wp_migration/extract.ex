defmodule Ysc.WpMigration.Extract do
  @moduledoc """
  Phase 1 extract: reads WordPress data from a DuckDB backup and writes
  the export directory (JSON files + iterable media folder).
  """

  require Ysc.Logging
  alias Ysc.WpMigration.{WpRepo, PhpDeserialize, HtmlTransformer}

  @doc """
  Runs the extract: opens the DuckDB file, writes users.json, applications.json,
  posts.json, stripe_customer_lookup.json, and media/<wp_attachment_id>/ (file + meta.json)
  into export_dir.

  Options:
  - :db          - path to the DuckDB file (from mix ysc.wp_to_duckdb; required)
  - :export_dir  - output path (default: "wp_migration_export")
  - :wp_files    - path to wp_backup/files (for resolving uploads; default: "wp_backup/files")
  - :dry_run     - if true, only log what would be written
  - :only_emails - a single email string or list of email strings; when provided,
                   only the matching users (and their associated applications, stripe
                   data, and bookings) are extracted. Useful for targeted test runs.
  """
  def run(opts \\ []) do
    db = opts[:db]
    export_dir = Path.expand(opts[:export_dir] || "wp_migration_export")
    wp_files = Path.expand(opts[:wp_files] || "wp_backup/files")
    dry_run = opts[:dry_run] || false

    only_emails =
      case opts[:only_emails] do
        nil ->
          nil

        email when is_binary(email) ->
          MapSet.new([String.downcase(email)])

        emails when is_list(emails) ->
          valid =
            emails |> Enum.filter(&is_binary/1) |> Enum.map(&String.downcase/1)

          if valid == [], do: nil, else: MapSet.new(valid)

        _ ->
          nil
      end

    if is_nil(db) or db == "" do
      {:error, "Missing :db (path to DuckDB file from mix ysc.wp_to_duckdb)"}
    else
      do_run(db, export_dir, wp_files, dry_run, only_emails)
    end
  end

  defp do_run(db, export_dir, wp_files, dry_run, only_emails) do
    case WpRepo.open(db) do
      {:ok, repo} ->
        try do
          if not dry_run do
            File.mkdir_p!(export_dir)
            File.mkdir_p!(Path.join(export_dir, "media"))
          end

          users =
            repo |> build_users() |> filter_by_emails(only_emails, "email")

          if only_emails,
            do:
              Ysc.Logging.info(
                "[WP Extract] :only_emails filter active — #{length(users)} matching users"
              )

          if dry_run, do: Ysc.Logging.info("Would write #{length(users)} users")
          write_json(export_dir, "users.json", users, dry_run)

          only_wp_user_ids =
            if only_emails, do: wp_user_id_set(users), else: nil

          applications =
            repo
            |> build_applications()
            |> filter_by_wp_user_ids(only_wp_user_ids, "wp_user_id")

          if dry_run,
            do:
              Ysc.Logging.info(
                "Would write #{length(applications)} applications"
              )

          write_json(export_dir, "applications.json", applications, dry_run)

          posts = build_posts(repo)
          if dry_run, do: Ysc.Logging.info("Would write #{length(posts)} posts")
          write_json(export_dir, "posts.json", posts, dry_run)

          stripe_lookup =
            repo
            |> build_stripe_customer_lookup()
            |> filter_by_wp_user_ids(only_wp_user_ids, "wp_user_id")

          write_json(
            export_dir,
            "stripe_customer_lookup.json",
            stripe_lookup,
            dry_run
          )

          bookings =
            repo
            |> build_bookings()
            |> filter_by_wp_user_ids(only_wp_user_ids, "wp_customer_user_id")

          if dry_run,
            do: Ysc.Logging.info("Would write #{length(bookings)} bookings")

          write_json(export_dir, "bookings.json", bookings, dry_run)

          media_uploads_root = Path.join(wp_files, "wp-content/uploads")
          copy_media(repo, export_dir, media_uploads_root, dry_run)

          {:ok, export_dir}
        after
          WpRepo.close(repo)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Returns a MapSet of wp_user_id values from a list of user rows.
  # When only_emails is nil (no filter), returns nil so downstream filters are skipped.
  defp wp_user_id_set(users) do
    users
    |> Enum.map(& &1["wp_user_id"])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  # Filters rows whose `email_field` (downcased) is in the given MapSet.
  # Passes through unchanged when only_emails is nil.
  defp filter_by_emails(rows, nil, _field), do: rows

  defp filter_by_emails(rows, only_emails, field) do
    Enum.filter(rows, fn row ->
      email = row[field]
      is_binary(email) and MapSet.member?(only_emails, String.downcase(email))
    end)
  end

  # Filters rows whose `id_field` value is in the given MapSet of wp_user_ids.
  # Passes through unchanged when only_wp_user_ids is nil (no filter active).
  defp filter_by_wp_user_ids(rows, nil, _field), do: rows

  defp filter_by_wp_user_ids(rows, only_wp_user_ids, field) do
    Enum.filter(rows, fn row -> MapSet.member?(only_wp_user_ids, row[field]) end)
  end

  defp build_users(repo) do
    repo
    |> WpRepo.list_users()
    |> Enum.map(fn row ->
      user_id = row["ID"]
      meta = WpRepo.get_usermeta(repo, user_id)
      {:ok, membership} = WpRepo.get_membership_for_user(repo, user_id)

      payments =
        case WpRepo.get_membership_payments_for_user(repo, user_id) do
          {:ok, p} -> p
          {:error, _reason} -> []
        end

      last_payment_date =
        case payments do
          [%{"payment_date" => d} | _] when d != "" -> normalize_datetime(d)
          _ -> nil
        end

      sub_status = presence(membership["sub_status"])

      has_active_wp_subscription =
        is_binary(sub_status) and sub_status in ["wc-active", "wc-on-hold"]

      %{
        "wp_user_id" => user_id,
        "email" => row["user_email"],
        "user_login" => row["user_login"],
        "user_registered" => normalize_datetime(row["user_registered"]),
        "display_name" => row["display_name"],
        "first_name" => meta["first_name"],
        "last_name" => meta["last_name"],
        "phone_number" => meta["phone_number"] || meta["billing_phone"],
        "address" => meta["address"] || meta["billing_address_1"],
        "city" => meta["city"] || meta["billing_city"],
        "state" => meta["billing_state"],
        "zip" => meta["zip"] || meta["billing_postcode"],
        "country" => meta["country"] || meta["billing_country"],
        "membership_type" => decode_membership_type(meta["membership_type"]),
        "account_status" => meta["account_status"],
        # UM profile timestamp (unix seconds); best available proxy for admin review date
        "last_update" => normalize_unix_timestamp(meta["last_update"]),
        "birth_date" => normalize_date(meta["birth_date"]),
        "citizenship" => meta["citizenship"],
        # WP key has a typo ("noedic"), so check both spellings
        "most_connected_country" =>
          meta["noedic_country_connected"] || meta["nordic_country_connected"] ||
            meta["citizenship"],
        "role" => meta["role"],
        # Membership & subscription status
        "wcm_status" => presence(membership["wcm_status"]),
        "wcm_start_date" => normalize_datetime(membership["wcm_start_date"]),
        "wcm_end_date" => normalize_datetime(membership["wcm_end_date"]),
        "sub_status" => sub_status,
        "sub_original_start_date" =>
          normalize_datetime(membership["sub_original_start_date"]),
        "sub_start_date" => normalize_datetime(membership["sub_start_date"]),
        "sub_next_payment_date" =>
          normalize_datetime(nil_if_zero(membership["sub_next_payment_date"])),
        "sub_amount" => presence(membership["sub_amount"]),
        "sub_period" => presence(membership["sub_period"]),
        # Payment-history-derived fields for date verification
        "last_membership_payment_date" => last_payment_date,
        "has_active_wp_subscription" => has_active_wp_subscription
      }
    end)
  end

  defp nil_if_zero(nil), do: nil
  defp nil_if_zero("0"), do: nil
  defp nil_if_zero(v), do: v

  defp build_applications(repo) do
    repo
    |> WpRepo.list_users()
    |> Enum.flat_map(fn row ->
      user_id = row["ID"]
      meta = WpRepo.get_usermeta(repo, user_id)

      app =
        build_application(
          user_id,
          row["user_email"],
          row["user_registered"],
          meta
        )

      [app]
    end)
  end

  # Build a structured application record.
  # If submitted (PHP-serialized) is present, parse it and prefer those
  # values (they are the canonical submission). Fall back to top-level usermeta
  # for users who were imported/created without a formal application.
  # Field names are intentionally aligned with the SignupApplication schema.
  defp build_application(user_id, email, user_registered, meta) do
    form = PhpDeserialize.parse_map(meta["submitted"])

    membership_type =
      decode_membership_type(form["membership_type"] || meta["membership_type"])

    membership_eligibility =
      form
      |> Map.get("checkbox_apply_to_you", %{})
      |> then(fn v -> if is_map(v), do: Map.values(v), else: [] end)
      |> Enum.map(&map_eligibility_string/1)
      |> Enum.reject(&is_nil/1)

    agreed_to_bylaws =
      case form["agree_checkbox"] do
        map when is_map(map) ->
          Map.values(map)
          |> Enum.any?(&String.contains?(&1, "Bylaws"))

        _ ->
          false
      end

    gender =
      case form["gender"] do
        map when is_map(map) -> map["0"]
        _ -> nil
      end

    # Address: prefer form submission → top-level usermeta → billing meta
    address =
      presence(form["address"]) || presence(meta["address"]) ||
        meta["billing_address_1"]

    city =
      presence(form["city"]) || presence(meta["city"]) || meta["billing_city"]

    postal_code =
      presence(form["zip"]) || presence(meta["zip"]) || meta["billing_postcode"]

    country =
      presence(form["country"]) || presence(meta["country"]) ||
        meta["billing_country"]

    region = presence(meta["billing_state"])

    most_connected_nordic_country =
      presence(form["noedic_country_connected"]) ||
        presence(meta["noedic_country_connected"]) ||
        presence(meta["nordic_country_connected"]) ||
        presence(form["citizenship"]) ||
        meta["citizenship"]

    citizenship = presence(form["citizenship"]) || meta["citizenship"]

    children =
      Enum.flat_map(1..4, fn i ->
        name_key = child_name_key(i)
        bday_key = child_birthday_key(i)
        name = presence(form[name_key]) || presence(meta[name_key])
        bday_raw = presence(form[bday_key]) || presence(meta[bday_key])

        if name,
          do: [
            %{"name" => name, "birthday" => normalize_child_birthday(bday_raw)}
          ],
          else: []
      end)

    %{
      "wp_user_id" => user_id,
      "email" => email,
      "membership_type" => membership_type,
      "membership_eligibility" => membership_eligibility,
      "gender" => gender,
      "first_name" => presence(form["first_name"]) || meta["first_name"],
      "last_name" => presence(form["last_name"]) || meta["last_name"],
      "phone_number" =>
        presence(form["phone_number"]) || meta["phone_number"] ||
          meta["billing_phone"],
      "occupation" => presence(form["occupation"]) || meta["occupation"],
      "birth_date" => normalize_date(form["birth_date"] || meta["birth_date"]),
      "place_of_birth" => presence(form["place_of_birth"]),
      "address" => address,
      "city" => city,
      "postal_code" => postal_code,
      "region" => region,
      "country" => country,
      "citizenship" => citizenship,
      "most_connected_nordic_country" => most_connected_nordic_country,
      # Essay / free-text questions (schema field names)
      "link_to_scandinavia" => presence(form["register_message_01"]),
      "lived_in_scandinavia" => presence(form["register_message_02"]),
      "spoken_languages" => presence(form["register_message_03"]),
      "hear_about_the_club" => presence(form["register_message_04"]),
      "agreed_to_bylaws" => agreed_to_bylaws,
      "spouse_first_name" =>
        presence(form["spouse_first_name"]) ||
          presence(meta["spouse_first_name"]),
      "spouse_last_name" =>
        presence(form["spouse_last_name"]) || presence(meta["spouse_last_name"]),
      "children" => children,
      "submitted_date" => normalize_datetime(user_registered),
      "has_submitted_application" => map_size(form) > 0
    }
  end

  # Map WP checkbox strings to MembershipEligibility enum values.
  # Strings in WP have trailing punctuation; match by substring.
  @eligibility_map [
    {"citizen of a Scandinavian country", "citizen_of_scandinavia"},
    {"born in Scandinavia", "born_in_scandinavia"},
    {"Scandinavian-born parent", "scandinavian_parent"},
    {"lived in Scandinavia", "lived_in_scandinavia"},
    {"speak one of the Scandinavian languages", "speak_scandinavian_language"},
    {"spouse of a member", "spouse_of_member"}
  ]

  defp map_eligibility_string(nil), do: nil
  defp map_eligibility_string(""), do: nil

  defp map_eligibility_string(text) when is_binary(text) do
    Enum.find_value(@eligibility_map, fn {fragment, value} ->
      if String.contains?(text, fragment), do: value
    end)
  end

  # Returns value only if non-nil and non-empty
  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v

  # ---------------------------------------------------------------------------
  # Date / datetime normalisation — target: ISO 8601 ("YYYY-MM-DD" / "YYYY-MM-DDTHH:MM:SS")
  # Input formats seen in the WP backup:
  #   "YYYY/MM/DD"           — form submission default
  #   "M/D/YYYY"             — US locale without leading zeros
  #   "YYYY-MM-DD"           — already ISO
  #   "YYYY-MM-DD HH:MM:SS"  — MySQL datetime (convert to ISO with T separator)
  #   "1900-01-00"           — MySQL zero-date placeholder → nil
  # ---------------------------------------------------------------------------

  defp normalize_date(nil), do: nil
  defp normalize_date(""), do: nil

  defp normalize_date(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      # YYYY/MM/DD or YYYY-MM-DD (with optional trailing time — strip it)
      Regex.match?(~r/^\d{4}[-\/]\d{2}[-\/]\d{2}/, value) ->
        date_part = String.slice(value, 0, 10) |> String.replace("/", "-")
        if valid_date?(date_part), do: date_part, else: nil

      # M/D/YYYY or MM/DD/YYYY (US locale without leading zeros)
      Regex.match?(~r/^\d{1,2}\/\d{1,2}\/\d{4}$/, value) ->
        [m, d, y] = String.split(value, "/")

        date_part =
          "#{y}-#{String.pad_leading(m, 2, "0")}-#{String.pad_leading(d, 2, "0")}"

        if valid_date?(date_part), do: date_part, else: nil

      true ->
        nil
    end
  end

  # Like normalize_date but also accepts a bare 4-digit year (common in WP usermeta).
  defp normalize_child_birthday(nil), do: nil
  defp normalize_child_birthday(""), do: nil
  defp normalize_child_birthday("0"), do: nil

  defp normalize_child_birthday(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      Regex.match?(~r/^\d{4}$/, value) -> value
      true -> normalize_date(value)
    end
  end

  defp normalize_unix_timestamp(nil), do: nil
  defp normalize_unix_timestamp(""), do: nil

  defp normalize_unix_timestamp(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {unix, ""} when unix > 0 ->
        unix
        |> DateTime.from_unix!(:second)
        |> DateTime.truncate(:second)
        |> Calendar.strftime("%Y-%m-%dT%H:%M:%S")

      _ ->
        nil
    end
  rescue
    ArgumentError -> nil
  end

  defp normalize_datetime(nil), do: nil
  defp normalize_datetime(""), do: nil

  defp normalize_datetime(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      # MySQL "YYYY-MM-DD HH:MM:SS" → "YYYY-MM-DDTHH:MM:SS"
      Regex.match?(~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/, value) ->
        if String.starts_with?(value, "1900-01-00") do
          nil
        else
          String.replace(value, " ", "T")
        end

      # Already ISO with T
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T/, value) ->
        value

      true ->
        # Fall back to date-only normalisation
        normalize_date(value)
    end
  end

  defp valid_date?(<<"1900-01-00", _::binary>>), do: false
  defp valid_date?(<<"0000-", _::binary>>), do: false

  defp valid_date?(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # Decode membership_type — handles PHP-serialized strings and already-parsed maps
  defp decode_membership_type(nil), do: nil
  defp decode_membership_type(""), do: nil

  defp decode_membership_type(map) when is_map(map) do
    # Already parsed by PhpDeserialize: %{"0" => "single"} → "single"
    map |> Map.values() |> List.first()
  end

  defp decode_membership_type(raw) when is_binary(raw) do
    case PhpDeserialize.parse(raw) do
      map when is_map(map) -> map |> Map.values() |> List.first()
      string when is_binary(string) -> string
      _ -> raw
    end
  end

  defp child_name_key(1), do: "first_child_name"
  defp child_name_key(2), do: "second_child_name"
  defp child_name_key(3), do: "third_child_name"
  defp child_name_key(4), do: "fourth_child_name"

  defp child_birthday_key(1), do: "first_child_birthday"
  defp child_birthday_key(2), do: "second_child_birthday"
  defp child_birthday_key(3), do: "third_child_birthday"
  defp child_birthday_key(4), do: "fourth_child_birthday"

  defp build_posts(repo) do
    repo
    |> WpRepo.list_published_posts()
    |> Enum.map(fn row ->
      post_id = row["ID"]
      meta = WpRepo.get_postmeta(repo, post_id)
      featured_id = meta["_thumbnail_id"]
      content = row["post_content"] || ""

      inline_ids = extract_attachment_ids_from_content(content)

      %{
        "wp_post_id" => post_id,
        "wp_author_id" => row["post_author"],
        "title" => row["post_title"],
        "post_name" => row["post_name"],
        "post_content" => content,
        "post_date" => normalize_datetime(row["post_date"]),
        "featured_image" => build_featured_image(repo, featured_id),
        "wp_attachment_ids_in_content" => Enum.uniq(inline_ids)
      }
    end)
  end

  defp build_featured_image(_repo, nil), do: nil
  defp build_featured_image(_repo, ""), do: nil

  defp build_featured_image(repo, attachment_id) do
    att_meta = WpRepo.get_postmeta(repo, attachment_id)
    attached_file = att_meta["_wp_attached_file"]

    ext = if attached_file, do: Path.extname(attached_file), else: ""

    {width, height} =
      case PhpDeserialize.parse_map(att_meta["_wp_attachment_metadata"]) do
        %{"width" => w, "height" => h} -> {to_int(w), to_int(h)}
        _ -> {nil, nil}
      end

    att_row = WpRepo.get_attachment(repo, attachment_id)
    mime_type = att_row && att_row["post_mime_type"]
    alt_text = att_meta["_wp_attachment_image_alt"]

    %{
      "wp_attachment_id" => attachment_id,
      # Path relative to the export directory where the file was copied
      "export_path" => "media/#{attachment_id}/file#{ext}",
      "original_filename" => attached_file && Path.basename(attached_file),
      "mime_type" => mime_type,
      "width" => width,
      "height" => height,
      "alt_text" => presence(alt_text)
    }
  end

  defp to_int(nil), do: nil
  defp to_int(n) when is_integer(n), do: n
  defp to_int(s) when is_binary(s), do: String.to_integer(s)

  defp extract_attachment_ids_from_content(content) do
    HtmlTransformer.extract_attachment_ids(content)
  end

  defp build_stripe_customer_lookup(repo) do
    repo
    |> WpRepo.list_users()
    |> Enum.map(fn row ->
      user_id = row["ID"]
      {:ok, stripe} = WpRepo.get_stripe_customer_for_user(repo, user_id)

      %{
        "wp_user_id" => user_id,
        "email" => row["user_email"],
        "stripe_customer_id" => stripe && stripe["stripe_customer_id"],
        "stripe_payment_method_id" =>
          stripe && stripe["stripe_payment_method_id"]
      }
    end)
  end

  defp build_bookings(repo) do
    repo
    |> WpRepo.list_future_mphb_bookings()
    |> Enum.map(&booking_to_export/1)
  end

  defp booking_to_export(row) do
    rooms = row["reserved_rooms"] || []

    guests_count =
      Enum.reduce(rooms, 0, fn r, acc -> acc + parse_int(r["adults"]) end)

    children_count =
      Enum.reduce(rooms, 0, fn r, acc -> acc + parse_int(r["children"]) end)

    %{
      "wp_booking_id" => row["ID"],
      "checkin_date" => presence(row["mphb_check_in_date"]),
      "checkout_date" => presence(row["mphb_check_out_date"]),
      "total_price" => presence(row["mphb_total_price"]),
      "wp_customer_user_id" => presence(row["mphb_customer_id"]),
      "guest_first_name" => presence(row["mphb_first_name"]),
      "guest_last_name" => presence(row["mphb_last_name"]),
      "guests_count" => guests_count,
      "children_count" => children_count,
      "rooms" =>
        Enum.map(rooms, fn r ->
          %{"wp_room_id" => r["wp_room_id"], "room_name" => r["room_name"]}
        end)
    }
  end

  defp parse_int(nil), do: 0
  defp parse_int(""), do: 0

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_int(v) when is_integer(v), do: v

  defp write_json(export_dir, filename, data, false) do
    path = Path.join(export_dir, filename)
    File.write!(path, Jason.encode!(data, escape: :unicode_safe))
  end

  defp write_json(_export_dir, _filename, _data, true), do: :ok

  defp copy_media(repo, export_dir, wp_uploads_root, dry_run) do
    media_dir = Path.join(export_dir, "media")

    attachments = WpRepo.list_attachments(repo)

    for att <- attachments do
      copy_one_attachment(repo, att["ID"], wp_uploads_root, media_dir, dry_run)
    end

    :ok
  end

  defp copy_one_attachment(
         repo,
         attachment_id,
         wp_uploads_root,
         media_dir,
         dry_run
       ) do
    path = WpRepo.get_attachment_path(repo, attachment_id, wp_uploads_root)

    if path && File.exists?(path) do
      subdir = Path.join(media_dir, to_string(attachment_id))

      if not dry_run do
        File.mkdir_p!(subdir)
        ext = Path.extname(path)
        dest_file = Path.join(subdir, "file#{ext}")
        File.cp!(path, dest_file)

        att_meta = WpRepo.get_postmeta(repo, attachment_id)
        att_row = WpRepo.get_attachment(repo, attachment_id)

        {width, height} =
          case PhpDeserialize.parse_map(att_meta["_wp_attachment_metadata"]) do
            %{"width" => w, "height" => h} -> {to_int(w), to_int(h)}
            _ -> {nil, nil}
          end

        meta = %{
          "wp_attachment_id" => attachment_id,
          "filename" => "file#{ext}",
          "original_filename" => Path.basename(path),
          "mime_type" => att_row && att_row["post_mime_type"],
          "width" => width,
          "height" => height,
          "alt_text" => presence(att_meta["_wp_attachment_image_alt"]),
          "title" => att_row && att_row["post_title"],
          "created" => normalize_datetime(att_row && att_row["post_date"])
        }

        File.write!(
          Path.join(subdir, "meta.json"),
          Jason.encode!(meta, escape: :unicode_safe)
        )
      end
    else
      Ysc.Logging.warning("Attachment not found or no path",
        attachment_id: attachment_id,
        path: path
      )
    end
  end

  @doc false
  def application_from_usermeta(user_id, email, user_registered, meta)
      when is_map(meta) do
    build_application(user_id, email, user_registered, meta)
  end
end
