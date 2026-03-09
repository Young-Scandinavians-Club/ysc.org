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
  alias Ysc.Bookings.{Booking, Room, BookingGuest}

  @doc """
  Runs the load. Reads export_dir (users.json, applications.json, posts.json, media/, stripe_customer_lookup.json)
  and inserts into the app DB. Optionally uploads media to S3 and creates Image records.

  Options:
  - :export_dir - path to export directory (required)
  - :dry_run - if true, do not write to DB or S3
  - :upload_media - if true, upload media folder to S3 and create Images (default: true)
  """
  def run(opts \\ []) do
    export_dir = opts[:export_dir] || opts["export_dir"]
    dry_run = opts[:dry_run] || opts["dry_run"] || false
    upload_media = Keyword.get(opts, :upload_media, true)

    if not export_dir do
      {:error, "Missing :export_dir"}
    else
      export_dir = Path.expand(export_dir)

      if not File.dir?(export_dir) do
        {:error, "Export directory not found: #{export_dir}"}
      else
        do_run(export_dir, dry_run, upload_media)
      end
    end
  end

  defp do_run(export_dir, dry_run, upload_media) do
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
          {:cont, {:ok, Map.put(acc, row["wp_user_id"], existing.id)}}

        nil ->
          state = map_account_status(row["account_status"])
          role = map_role(row["role"])

          attrs = %{
            "email" => email,
            "first_name" =>
              row["first_name"] || row["display_name"] || "Unknown",
            "last_name" => row["last_name"] || "User",
            "phone_number" => row["phone_number"],
            "state" => state,
            "role" => role,
            "most_connected_country" =>
              row["nordic_country_connected"] || row["Country"]
          }

          changeset =
            %User{}
            |> User.registration_changeset(attrs,
              require_password: false,
              validate_email: false,
              hash_password: false
            )

          case Repo.insert(changeset) do
            {:ok, user} ->
              # Address
              if row["Address"] && row["Country"] do
                %Address{}
                |> Address.changeset(%{
                  user_id: user.id,
                  address: row["Address"],
                  city: row["City"],
                  region: row["State"],
                  postal_code: row["Zip code"],
                  country: row["Country"]
                })
                |> Repo.insert()
              end

              {:cont, {:ok, Map.put(acc, row["wp_user_id"], user.id)}}

            {:error, changeset} ->
              Ysc.Logging.warning("Failed to insert user",
                email: email,
                errors: inspect(changeset.errors)
              )

              {:halt, {:error, changeset}}
          end
      end
    end)
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

      if not user_id do
        {:cont, {:ok, :done}}
      else
        if Repo.get_by(SignupApplication, user_id: user_id),
          do: {:cont, {:ok, :done}}

        birth_date = parse_date(row["birth_date"])

        attrs = %{
          user_id: user_id,
          membership_type: (row["membership_type"] || "single") |> to_string(),
          birth_date: birth_date,
          address: row["Address"],
          city: row["City"],
          region: row["State"],
          postal_code: row["Zip code"],
          country: row["Country"],
          citizenship: row["citizenship"],
          most_connected_nordic_country: row["nordic_country_connected"]
        }

        case %SignupApplication{}
             |> SignupApplication.application_changeset(attrs)
             |> Repo.insert() do
          {:ok, _} -> {:cont, {:ok, :done}}
          {:error, cs} -> {:halt, {:error, cs}}
        end
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

        if not file_path or not File.exists?(file_path) do
          {:cont, {:ok, acc}}
        else
          meta =
            if File.exists?(meta_path),
              do: File.read!(meta_path) |> Jason.decode!(),
              else: %{}

          key = "migration/#{att_id}/#{Path.basename(file_path)}"

          case Media.upload_file_to_s3(file_path, key) do
            %{body: %{location: location}} when is_binary(location) ->
              attrs = %{
                raw_image_path: URI.encode(location),
                user_id: uploader.id,
                title: meta["title"]
              }

              case %Image{}
                   |> Image.add_image_changeset(attrs)
                   |> Repo.insert() do
                {:ok, img} -> {:cont, {:ok, Map.put(acc, att_id, img.id)}}
                {:error, _} -> {:cont, {:ok, acc}}
              end

            _ ->
              {:cont, {:ok, acc}}
          end
        end
      end)
    end
  end

  defp load_posts(posts_data, user_map, image_map) do
    author_fallback =
      Repo.one(from u in User, where: u.role == ^:admin, limit: 1) ||
        Repo.one(User)

    Enum.reduce_while(posts_data, {:ok, :done}, fn row, {:ok, _} ->
      author_id =
        user_map[row["wp_author_id"]] || (author_fallback && author_fallback.id)

      if not author_id, do: {:cont, {:ok, :done}}

      image_id =
        row["wp_featured_attachment_id"] &&
          image_map[row["wp_featured_attachment_id"]]

      url_name = row["post_name"] || slugify(row["title"])
      published_on = parse_datetime(row["post_date"])

      attrs = %{
        user_id: author_id,
        state: "published",
        title: row["title"],
        url_name: url_name,
        raw_body: row["post_content"],
        rendered_body: row["post_content"],
        published_on: published_on,
        image_id: image_id
      }

      case %Post{}
           |> Post.new_post_changeset(attrs, validate_url_name: false)
           |> Repo.insert() do
        {:ok, _} ->
          {:cont, {:ok, :done}}

        {:error, cs} ->
          if Keyword.get(cs.errors, :url_name) do
            attrs =
              Map.put(attrs, :url_name, url_name <> "-" <> row["wp_post_id"])

            case %Post{}
                 |> Post.new_post_changeset(attrs, validate_url_name: false)
                 |> Repo.insert() do
              {:ok, _} -> {:cont, {:ok, :done}}
              {:error, _} -> {:halt, {:error, cs}}
            end
          else
            {:halt, {:error, cs}}
          end
      end
    end)
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
    case NaiveDateTime.from_iso8601(str <> " 00:00:00") do
      {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp load_stripe(stripe_data, user_map) do
    for row <- stripe_data do
      user_id = user_map[row["wp_user_id"]]
      cus_id = row["stripe_customer_id"]

      if user_id && cus_id && cus_id != "" do
        user = Repo.get!(User, user_id)
        user = Repo.preload(user, [])

        if user.stripe_id != cus_id do
          user
          |> User.update_user_changeset(%{stripe_id: cus_id})
          |> Repo.update()
        end

        # TODO: list payment methods, persist; create subscription for single/family approved
      end
    end

    :ok
  end

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
              total_price = parse_booking_money(row["total_price"])

              attrs = %{
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
