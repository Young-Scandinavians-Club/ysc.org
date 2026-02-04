# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Ysc.Repo.insert!(%Ysc.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Ysc.Repo
alias Ysc.Accounts.{Address, User}
alias Ysc.SiteSettings.SiteSetting
alias Ysc.Bookings
import Ecto.Query

# Default settings
Repo.insert!(
  SiteSetting.site_setting_changeset(%SiteSetting{}, %{
    group: "socials",
    name: "instagram",
    value: "https://www.instagram.com/theysc"
  }),
  on_conflict: :nothing
)

Repo.insert!(
  SiteSetting.site_setting_changeset(%SiteSetting{}, %{
    group: "socials",
    name: "facebook",
    value: "https://www.facebook.com/YoungScandinaviansClub/"
  }),
  on_conflict: :nothing
)

Repo.insert!(
  SiteSetting.site_setting_changeset(%SiteSetting{}, %{
    group: "socials",
    name: "discord",
    value: "https://discord.gg/dn2gdXRZbW"
  }),
  on_conflict: :nothing
)

first_names = [
  "Karl",
  "Erik",
  "Lars",
  "Anders",
  "Per",
  "Mikael",
  "Johan",
  "Olof",
  "Nils",
  "Jan",
  "Maria",
  "Elisabeth",
  "Anna",
  "Kristina",
  "Margareta",
  "Eva",
  "Linnéa",
  "Karin",
  "Birgitta",
  "Marie"
]

last_names = [
  "Andersson",
  "Johansson",
  "Karlsson",
  "Nilsson",
  "Eriksson",
  "Larsson",
  "Olsson",
  "Persson",
  "Svensson",
  "Gustafsson",
  "Pettersson",
  "Jonsson",
  "Jansson",
  "Hansson",
  "Bengtsson",
  "Jönsson",
  "Lindberg",
  "Berg",
  "Lind",
  "Lundgren",
  "Lindgren",
  "Sandberg",
  "Eklund"
]

countries = [
  "SE",
  "NO",
  "FI",
  "IS",
  "DK"
]

n_approved_users = 9
n_pending_users = 5
n_rejected_users = 3
n_deleted_users = 2

# Helper function to create address from registration form
create_address_for_user = fn user ->
  # Preload registration_form to get address data
  user = Repo.preload(user, :registration_form)

  case user.registration_form do
    %{
      address: address,
      city: city,
      country: country,
      postal_code: postal_code,
      region: region
    }
    when not is_nil(address) and not is_nil(city) and not is_nil(country) and
           not is_nil(postal_code) ->
      # Check if address already exists
      existing_address = Repo.get_by(Address, user_id: user.id)

      if existing_address do
        :ok
      else
        case %Address{}
             |> Address.from_signup_application_changeset(
               user.registration_form
             )
             |> Ecto.Changeset.put_change(:user_id, user.id)
             |> Repo.insert() do
          {:ok, _address} ->
            :ok

          {:error, changeset} ->
            IO.puts(
              "Failed to create address for user #{user.email}: #{inspect(changeset.errors)}"
            )

            :ok
        end
      end

    _ ->
      # No registration form or missing address fields
      :ok
  end
end

# Helper function to mark email as verified and password as set
# This ensures seeded users can skip email verification and password setup
mark_user_verified = fn user ->
  now = DateTime.utc_now() |> DateTime.truncate(:second)

  user
  |> Ecto.Changeset.change()
  |> Ecto.Changeset.put_change(:email_verified_at, now)
  |> Ecto.Changeset.put_change(:password_set_at, now)
  |> Repo.update()
  |> case do
    {:ok, updated_user} ->
      updated_user

    {:error, changeset} ->
      IO.puts(
        "Failed to mark user #{user.email} as verified: #{inspect(changeset.errors)}"
      )

      user
  end
end

# Get or create admin user
admin_user =
  case Repo.get_by(User, email: "admin@ysc.org") do
    nil ->
      admin_changeset =
        User.registration_changeset(%User{}, %{
          email: "admin@ysc.org",
          password: "very_secure_password",
          role: :admin,
          state: :active,
          first_name: "Admin",
          last_name: "User",
          phone_number: "+14159009009",
          most_connected_country: countries |> Enum.shuffle() |> hd(),
          confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          date_of_birth: ~D[1980-01-15],
          registration_form: %{
            membership_type: "family",
            membership_eligibility: [
              "citizen_of_scandinavia",
              "born_in_scandinavia"
            ],
            occupation: "Plumber",
            birth_date: "1980-01-15",
            address: "Dance St 2",
            country: "USA",
            city: "Dance Town",
            region: "CA",
            postal_code: "94700",
            place_of_birth: "Norway",
            citizenship: "USA",
            most_connected_nordic_country: "Norway",
            link_to_scandinavia: "Love it!",
            lived_in_scandinavia: "For a few seconds.",
            spoken_languages: "English and German",
            hear_about_the_club: "On internet",
            agreed_to_bylaws: "true",
            agreed_to_bylaws_at:
              DateTime.utc_now() |> DateTime.truncate(:second),
            started: DateTime.utc_now() |> DateTime.truncate(:second),
            completed: DateTime.utc_now() |> DateTime.truncate(:second),
            browser_timezone: "America/Los_Angeles"
          }
        })

      case Repo.insert(admin_changeset, on_conflict: :nothing) do
        {:ok, user} when not is_nil(user) ->
          # Create billing address from registration form
          create_address_for_user.(user)
          # Mark email as verified and password as set
          mark_user_verified.(user)

        {:ok, nil} ->
          # Conflict occurred, fetch the existing user
          user = Repo.get_by!(User, email: "admin@ysc.org")
          # Ensure address exists for existing admin user
          create_address_for_user.(user)
          # Mark email as verified and password as set
          mark_user_verified.(user)

        {:error, _changeset} ->
          # If insert fails, try to fetch again (might have been created by another process)
          user =
            Repo.get_by!(User, email: "admin@ysc.org") ||
              raise("Failed to create or find admin user")

          # Ensure address exists for existing admin user
          create_address_for_user.(user)
          # Mark email as verified and password as set
          mark_user_verified.(user)
      end

    existing_user ->
      # Ensure address exists for existing admin user
      create_address_for_user.(existing_user)
      # Mark email as verified and password as set
      mark_user_verified.(existing_user)
  end

Enum.each(0..n_approved_users, fn n ->
  membership_type =
    if rem(n, 2) == 0 do
      "single"
    else
      "family"
    end

  last_name = last_names |> Enum.shuffle() |> hd()

  fam_members =
    if membership_type == "family" do
      [
        %{
          first_name: first_names |> Enum.shuffle() |> hd(),
          last_name: last_name,
          birth_date: "1990-06-06",
          type: "spouse"
        },
        %{
          first_name: first_names |> Enum.shuffle() |> hd(),
          last_name: last_name,
          birth_date: "1999-08-08",
          type: "child"
        }
      ]
    else
      []
    end

  first_name = first_names |> Enum.shuffle() |> hd()
  email = String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org")

  # Check if user already exists
  existing_user = Repo.get_by(User, email: email)

  if existing_user do
    IO.puts("User already exists, skipping: #{email}")
  else
    # Generate a reasonable birth date (between 1980 and 2000)
    birth_year = 1980 + rem(n, 20)
    birth_month = 1 + rem(n, 12)
    birth_day = 1 + rem(n, 28)
    birth_date = Date.new!(birth_year, birth_month, birth_day)

    regular_user =
      User.registration_changeset(%User{}, %{
        email: email,
        password: "very_secure_password",
        role: :member,
        state: :active,
        first_name: first_name,
        last_name: last_name,
        phone_number: "+1415900900#{n}",
        confirmed_at: DateTime.utc_now(),
        most_connected_country: countries |> Enum.shuffle() |> hd(),
        date_of_birth: birth_date,
        family_members: fam_members,
        registration_form: %{
          membership_type: membership_type,
          membership_eligibility: [
            "citizen_of_scandinavia",
            "born_in_scandinavia"
          ],
          occupation: "Plumber",
          birth_date: Date.to_iso8601(birth_date),
          address: "Dance St 2",
          country: "USA",
          city: "Dance Town",
          region: "CA",
          postal_code: "94700",
          place_of_birth: "Sweden",
          citizenship: "USA",
          most_connected_nordic_country: "Sweden",
          link_to_scandinavia: "Love it!",
          lived_in_scandinavia: "For a few seconds.",
          spoken_languages: "English and German",
          hear_about_the_club: "On internet",
          agreed_to_bylaws: "true",
          agreed_to_bylaws_at: DateTime.utc_now(),
          started: DateTime.utc_now(),
          completed: DateTime.utc_now(),
          browser_timezone: "America/Los_Angeles",
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          review_outcome: "approved",
          reviewed_by_user_id: admin_user.id
        }
      })

    case Repo.insert(regular_user, on_conflict: :nothing) do
      {:ok, user} ->
        # Create billing address from registration form
        create_address_for_user.(user)
        # Mark email as verified and password as set
        mark_user_verified.(user)
        :ok

      {:error, changeset} ->
        IO.puts("Failed to create user #{email}: #{inspect(changeset.errors)}")
    end
  end
end)

Enum.each(0..n_pending_users, fn n ->
  membership_type =
    if rem(n, 2) == 0 do
      "single"
    else
      "family"
    end

  last_name = last_names |> Enum.shuffle() |> hd()

  fam_members =
    if membership_type == "family" do
      [
        %{
          first_name: first_names |> Enum.shuffle() |> hd(),
          last_name: last_name,
          birth_date: "1990-06-06",
          type: "spouse"
        },
        %{
          first_name: first_names |> Enum.shuffle() |> hd(),
          last_name: last_name,
          birth_date: "1999-08-08",
          type: "child"
        }
      ]
    else
      []
    end

  first_name = first_names |> Enum.shuffle() |> hd()
  email = String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org")

  # Check if user already exists
  existing_user = Repo.get_by(User, email: email)

  if existing_user do
    IO.puts("User already exists, skipping: #{email}")
  else
    # Generate a reasonable birth date (between 1985 and 2005)
    birth_year = 1985 + rem(n, 20)
    birth_month = 1 + rem(n, 12)
    birth_day = 1 + rem(n, 28)
    birth_date = Date.new!(birth_year, birth_month, birth_day)

    pending_user =
      User.registration_changeset(%User{}, %{
        email: email,
        password: "very_secure_password",
        role: :member,
        state: :pending_approval,
        first_name: first_name,
        last_name: last_name,
        phone_number: "+1415900900#{n}",
        confirmed_at: DateTime.utc_now(),
        most_connected_country: countries |> Enum.shuffle() |> hd(),
        date_of_birth: birth_date,
        family_members: fam_members,
        registration_form: %{
          membership_type: membership_type,
          membership_eligibility: [
            "citizen_of_scandinavia",
            "born_in_scandinavia"
          ],
          occupation: "Plumber",
          birth_date: Date.to_iso8601(birth_date),
          address: "Dance St 2",
          country: "USA",
          city: "Dance Town",
          region: "CA",
          postal_code: "9470#{n}",
          place_of_birth: "Sweden",
          citizenship: "USA",
          most_connected_nordic_country: "Sweden",
          link_to_scandinavia: "Love it!",
          lived_in_scandinavia: "For a few seconds.",
          spoken_languages: "English and German",
          hear_about_the_club: "On internet",
          agreed_to_bylaws: "true",
          agreed_to_bylaws_at: DateTime.utc_now(),
          started: DateTime.utc_now(),
          completed: DateTime.utc_now(),
          browser_timezone: "America/Los_Angeles"
        }
      })

    case Repo.insert(pending_user, on_conflict: :nothing) do
      {:ok, user} ->
        # Create billing address from registration form
        create_address_for_user.(user)
        # Mark email as verified and password as set
        mark_user_verified.(user)
        :ok

      {:error, changeset} ->
        IO.puts("Failed to create user #{email}: #{inspect(changeset.errors)}")
    end
  end
end)

Enum.each(0..n_rejected_users, fn n ->
  first_name = first_names |> Enum.shuffle() |> hd()
  last_name = last_names |> Enum.shuffle() |> hd()
  email = String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org")

  # Check if user already exists
  existing_user = Repo.get_by(User, email: email)

  if existing_user do
    IO.puts("User already exists, skipping: #{email}")
  else
    # Generate a reasonable birth date (between 1975 and 1995)
    birth_year = 1975 + rem(n, 20)
    birth_month = 1 + rem(n, 12)
    birth_day = 1 + rem(n, 28)
    birth_date = Date.new!(birth_year, birth_month, birth_day)

    rejected_user =
      User.registration_changeset(%User{}, %{
        email: email,
        password: "very_secure_password",
        role: :member,
        state: :rejected,
        first_name: first_name,
        last_name: last_name,
        phone_number: "+1415900900#{n}",
        most_connected_country: countries |> Enum.shuffle() |> hd(),
        date_of_birth: birth_date,
        registration_form: %{
          membership_type: "family",
          membership_eligibiltiy: [],
          occupation: "Plumber",
          birth_date: Date.to_iso8601(birth_date),
          address: "Dance St 2",
          country: "USA",
          city: "Dance Town",
          region: "CA",
          postal_code: "94700",
          place_of_birth: "USA",
          citizenship: "USA",
          most_connected_nordic_country: "Iceland",
          link_to_scandinavia: "Love it!",
          lived_in_scandinavia: "For a few seconds.",
          spoken_languages: "English",
          hear_about_the_club: "On internet",
          agreed_to_bylaws: "true",
          agreed_to_bylaws_at: DateTime.utc_now(),
          started: DateTime.utc_now(),
          completed: DateTime.utc_now(),
          browser_timezone: "America/Los_Angeles",
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          review_outcome: "rejected",
          reviewed_by_user_id: admin_user.id
        }
      })

    case Repo.insert(rejected_user, on_conflict: :nothing) do
      {:ok, user} ->
        # Create billing address from registration form
        create_address_for_user.(user)
        # Mark email as verified and password as set
        mark_user_verified.(user)
        :ok

      {:error, changeset} ->
        IO.puts("Failed to create user #{email}: #{inspect(changeset.errors)}")
    end
  end
end)

Enum.each(0..n_deleted_users, fn n ->
  first_name = first_names |> Enum.shuffle() |> hd()
  last_name = last_names |> Enum.shuffle() |> hd()
  email = String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org")

  # Check if user already exists
  existing_user = Repo.get_by(User, email: email)

  if existing_user do
    IO.puts("User already exists, skipping: #{email}")
  else
    # Generate a reasonable birth date (between 1980 and 2000)
    birth_year = 1980 + rem(n, 20)
    birth_month = 1 + rem(n, 12)
    birth_day = 1 + rem(n, 28)
    birth_date = Date.new!(birth_year, birth_month, birth_day)

    deleted_user =
      User.registration_changeset(%User{}, %{
        email: email,
        password: "very_secure_password",
        role: :member,
        state: :deleted,
        first_name: first_name,
        last_name: last_name,
        phone_number: "+1415900900#{n}",
        most_connected_country: countries |> Enum.shuffle() |> hd(),
        date_of_birth: birth_date,
        registration_form: %{
          membership_type: "family",
          membership_eligibility: [],
          occupation: "Plumber",
          birth_date: Date.to_iso8601(birth_date),
          address: "Dance St 2",
          country: "USA",
          city: "Dance Town",
          region: "CA",
          postal_code: "94700",
          place_of_birth: "USA",
          citizenship: "USA",
          most_connected_nordic_country: "Iceland",
          link_to_scandinavia: "Love it!",
          lived_in_scandinavia: "For a few seconds.",
          spoken_languages: "English",
          hear_about_the_club: "On internet",
          agreed_to_bylaws: "true",
          agreed_to_bylaws_at: DateTime.utc_now(),
          started: DateTime.utc_now(),
          completed: DateTime.utc_now(),
          browser_timezone: "America/Los_Angeles",
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          review_outcome: "approved",
          reviewed_by_user_id: admin_user.id
        }
      })

    case Repo.insert(deleted_user, on_conflict: :nothing) do
      {:ok, user} ->
        # Create billing address from registration form
        create_address_for_user.(user)
        # Mark email as verified and password as set
        mark_user_verified.(user)
        :ok

      {:error, changeset} ->
        IO.puts("Failed to create user #{email}: #{inspect(changeset.errors)}")
    end
  end
end)

# Seed random user notes
alias Ysc.Accounts

# Get some users to add notes to (mix of different states)
users_for_notes =
  Repo.all(
    from u in User,
      where: u.email != "admin@ysc.org",
      limit: 15
  )

if length(users_for_notes) > 0 and admin_user do
  general_notes = [
    "User contacted support about membership renewal",
    "Attended the annual summer event in 2024",
    "Very active member, participates in most events",
    "Requested information about family membership benefits",
    "Interested in volunteering for upcoming events",
    "Moved to a new address, updated billing information",
    "Attended cabin booking orientation session",
    "Participated in the Nordic cooking workshop",
    "Referred a friend who joined the club",
    "Asked about event ticket pricing",
    "Very engaged in Discord community discussions",
    "Attended multiple social gatherings this year",
    "Helped organize the winter holiday event",
    "Requested information about Scandinavian language classes",
    "Active participant in book club meetings"
  ]

  violation_notes = [
    "Reported for inappropriate behavior at social event",
    "Violated cabin booking cancellation policy",
    "Failed to follow event attendance guidelines",
    "Reported for disruptive behavior in online community",
    "Did not comply with membership code of conduct",
    "Violated payment terms for event registration",
    "Reported for inappropriate language in group chat",
    "Failed to respect other members' privacy",
    "Violated event photography policy",
    "Reported for not following cabin checkout procedures"
  ]

  # Add 2-4 random notes to each user
  Enum.each(users_for_notes, fn user ->
    # 2-4 notes per user
    num_notes = 2 + :rand.uniform(3)

    Enum.each(1..num_notes, fn _ ->
      # 70% chance of general note, 30% chance of violation
      is_violation = :rand.uniform(10) <= 3
      category = if is_violation, do: "violation", else: "general"
      notes_pool = if is_violation, do: violation_notes, else: general_notes
      note_text = notes_pool |> Enum.shuffle() |> hd()

      # Add some variation to make notes more unique
      variations = [
        "",
        " Follow-up needed.",
        " Resolved.",
        " No action required.",
        " Will monitor."
      ]

      final_note = note_text <> (variations |> Enum.shuffle() |> hd())

      case Accounts.create_user_note(
             user,
             %{"note" => final_note, "category" => category},
             admin_user
           ) do
        {:ok, _note} -> :ok
        # Silently skip if there's an error
        {:error, _error} -> :ok
      end
    end)
  end)

  IO.puts("✓ Added random notes to #{length(users_for_notes)} users")
end

# Seed Posts and Events with Images
alias Ysc.Posts
alias Ysc.Posts.Post
alias Ysc.Events
alias Ysc.Events.Event
alias Ysc.Media
alias Ysc.Media.Image
alias Ysc.Agendas

# Get active users for creating posts and events
active_users = Repo.all(from u in User, where: u.state == :active, limit: 10)

if length(active_users) > 0 do
  # Seed directory for images
  seed_assets_dir = Path.join([File.cwd!(), "etc", "seed", "assets"])

  # Upload images to S3 and create Image records
  # Use admin_user for image creation since it requires admin role
  uploaded_images =
    if File.exists?(seed_assets_dir) do
      seed_assets_dir
      |> File.ls!()
      |> Enum.filter(&String.contains?(&1, [".jpg", ".jpeg", ".png", ".webp"]))
      |> Enum.with_index()
      |> Enum.map(fn {filename, index} ->
        image_path = Path.join(seed_assets_dir, filename)

        image_title =
          String.replace(filename, ~r/[_-]/, " ")
          |> String.replace(~r/\.[^.]*$/, "")

        # Check if image already exists by title
        existing_image =
          Repo.one(
            from i in Image,
              where: i.title == ^image_title,
              limit: 1
          )

        if existing_image do
          IO.puts("Image already exists, skipping: #{filename}")
          existing_image
        else
          # Upload raw file to S3
          upload_result =
            try do
              Media.upload_file_to_s3(image_path)
            rescue
              e ->
                IO.puts("Failed to upload #{filename} to S3: #{inspect(e)}")
                nil
            end

          if upload_result do
            raw_s3_path = upload_result[:body][:location]

            # Check if image with this raw_image_path already exists
            existing_by_path =
              Repo.one(
                from i in Image,
                  where: i.raw_image_path == ^URI.encode(raw_s3_path),
                  limit: 1
              )

            if existing_by_path do
              IO.puts("Image with path already exists, skipping: #{filename}")
              existing_by_path
            else
              # Create image record (must use admin_user for authorization)
              case Media.add_new_image(
                     %{
                       raw_image_path: URI.encode(raw_s3_path),
                       user_id: admin_user.id,
                       title: image_title,
                       processing_state: "unprocessed"
                     },
                     admin_user
                   ) do
                {:ok, new_image} ->
                  # Process the image (create thumbnails, optimized versions, blur hash)
                  temp_dir = "/tmp/image_processor"
                  File.mkdir_p!(temp_dir)
                  tmp_output_file = "#{temp_dir}/#{new_image.id}"

                  # Format will be determined dynamically in process_image_upload
                  optimized_output_path = "#{tmp_output_file}_optimized"
                  thumbnail_output_path = "#{tmp_output_file}_thumb"

                  processed_image =
                    try do
                      Media.process_image_upload(
                        new_image,
                        image_path,
                        thumbnail_output_path,
                        optimized_output_path
                      )
                    rescue
                      e ->
                        # If image processing fails, at least we have the raw image
                        IO.puts(
                          "Failed to process image #{filename}: #{inspect(e)}"
                        )

                        new_image
                    end

                  # Clean up temp files (including any format extensions)
                  try do
                    # Clean up the downloaded file
                    File.rm(tmp_output_file)
                    # Clean up processed files with any extension
                    ["_optimized", "_thumb"]
                    |> Enum.each(fn suffix ->
                      [".jpg", ".jpeg", ".png", ".webp"]
                      |> Enum.each(fn ext ->
                        path = "#{tmp_output_file}#{suffix}#{ext}"
                        if File.exists?(path), do: File.rm(path)
                      end)
                    end)

                    File.rmdir(temp_dir)
                  rescue
                    _ -> :ok
                  end

                  # Clean up any PNG files that might have been created in the seed directory
                  # (Blurhash might create temporary PNG files)
                  seed_png_path =
                    String.replace(image_path, ~r/\.[^.]+$/, ".png")

                  if File.exists?(seed_png_path) and seed_png_path != image_path do
                    try do
                      File.rm(seed_png_path)

                      IO.puts(
                        "Cleaned up temporary PNG file: #{Path.basename(seed_png_path)}"
                      )
                    rescue
                      _ -> :ok
                    end
                  end

                  processed_image

                {:error, reason} ->
                  IO.puts(
                    "Failed to create image record for #{filename}: #{inspect(reason)}"
                  )

                  nil
              end
            end
          else
            nil
          end
        end
      end)
      |> Enum.filter(&(&1 != nil))
    else
      []
    end

  if length(uploaded_images) > 0 do
    IO.puts("Uploaded #{length(uploaded_images)} images to S3")

    # Create example posts
    post_titles = [
      "Welcome to the Young Scandinavians Club",
      "Annual Midsummer Celebration Coming Up",
      "Scandinavian Cooking Class: Traditional Recipes",
      "Hiking Trip to Yosemite National Park",
      "Nordic Book Club: February Selection"
    ]

    post_contents = [
      """
      We're excited to welcome all new members to the Young Scandinavians Club!

      Our club has been fostering connections among young Scandinavians living in the Bay Area for over a decade. We organize regular events, cultural activities, and provide a supportive community for Scandinavians away from home.

      Whether you're from Sweden, Norway, Denmark, Finland, or Iceland, you'll find a warm welcome here. Join us for our upcoming events and meet fellow Scandinavians!
      """,
      """
      Join us for our annual Midsummer celebration! This is one of our most popular events of the year.

      **Event Details:**
      - Traditional midsummer pole raising
      - Folk dancing and music
      - Traditional Scandinavian food
      - Activities for all ages

      Don't miss this opportunity to celebrate Scandinavian traditions with friends and family!
      """,
      """
      Learn to cook traditional Scandinavian dishes in our hands-on cooking class.

      In this class, you'll learn to make:
      - Swedish meatballs
      - Norwegian salmon
      - Danish pastries
      - Finnish cinnamon buns

      All ingredients provided. Bring your appetite and curiosity!
      """,
      """
      Explore the great outdoors with fellow club members on our annual hiking trip to Yosemite.

      We'll be hiking some of the most beautiful trails, sharing stories, and enjoying nature. This is a great way to connect with other outdoor enthusiasts in the club.

      All experience levels welcome!
      """,
      """
      This month's book club selection is "Beartown" by Fredrik Backman.

      Join us for a lively discussion about this acclaimed Swedish novel. Whether you've read it before or it's your first time, all perspectives are welcome.

      We meet on the last Thursday of each month. Coffee and pastries provided!
      """
    ]

    Enum.each(0..(length(post_titles) - 1), fn index ->
      title = Enum.at(post_titles, index)

      try do
        # Check if post already exists by title
        existing_post =
          Repo.one(from p in Post, where: p.title == ^title, limit: 1)

        if existing_post do
          IO.puts("Post already exists, skipping: #{title}")
        else
          content = Enum.at(post_contents, index)
          # Use admin_user for post creation since it requires admin role
          user = admin_user
          image = Enum.at(uploaded_images, rem(index, length(uploaded_images)))

          url_name =
            title
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9]+/, "-")
            |> String.trim("-")
            |> then(fn name ->
              "#{name}-#{System.system_time(:second) - index}"
            end)

          published_on = DateTime.add(DateTime.utc_now(), -index * 2, :day)

          case Posts.create_post(
                 %{
                   "title" => title,
                   "url_name" => url_name,
                   "raw_body" => content,
                   "rendered_body" => content,
                   "preview_text" => String.slice(content, 0..150) <> "...",
                   "state" => "published",
                   "image_id" => image.id,
                   "featured_post" => index == 0,
                   "published_on" => published_on
                 },
                 user
               ) do
            {:ok, post} ->
              IO.puts("Created post: #{post.title}")

            {:error, changeset} ->
              IO.puts(
                "Failed to create post: #{title} - #{inspect(changeset.errors)}"
              )
          end
        end
      rescue
        e ->
          IO.puts("Error creating post '#{title}': #{inspect(e)}")
      end
    end)

    # Helper function to generate agenda items based on event type
    generate_agenda_items = fn event_title, start_time, end_time ->
      # Extract hour from start_time
      start_hour = start_time.hour
      start_minute = start_time.minute
      end_hour = end_time.hour
      end_minute = end_time.minute

      # Calculate total duration in minutes
      total_minutes =
        end_hour * 60 + end_minute - (start_hour * 60 + start_minute)

      # Generate agenda items based on event type
      items =
        cond do
          String.contains?(String.downcase(event_title), "gala") or
              String.contains?(String.downcase(event_title), "dinner") ->
            [
              %{
                title: "Welcome Reception",
                description: "Cocktails and mingling",
                duration: 30
              },
              %{
                title: "Opening Remarks",
                description: "Welcome address from club leadership",
                duration: 15
              },
              %{
                title: "First Course",
                description: "Traditional appetizers",
                duration: 25
              },
              %{
                title: "Main Course",
                description: "Scandinavian specialties",
                duration: 45
              },
              %{
                title: "Entertainment",
                description: "Live music and performances",
                duration: 40
              },
              %{
                title: "Dessert & Coffee",
                description: "Traditional desserts and coffee service",
                duration: 30
              },
              %{
                title: "Closing Remarks",
                description: "Thank you and announcements",
                duration: 10
              }
            ]

          String.contains?(String.downcase(event_title), "book") ->
            [
              %{
                title: "Welcome & Introductions",
                description: "Meet fellow readers",
                duration: 15
              },
              %{
                title: "Book Discussion",
                description: "Deep dive into this month's selection",
                duration: 60
              },
              %{
                title: "Q&A Session",
                description: "Questions and sharing",
                duration: 20
              },
              %{
                title: "Next Month Preview",
                description: "Introduction to next month's book",
                duration: 10
              }
            ]

          String.contains?(String.downcase(event_title), "cultural") ->
            [
              %{
                title: "Welcome & Registration",
                description: "Check-in and welcome refreshments",
                duration: 30
              },
              %{
                title: "Opening Presentation",
                description: "Introduction to Scandinavian culture",
                duration: 20
              },
              %{
                title: "Food & Drink Tasting",
                description: "Sample traditional Scandinavian cuisine",
                duration: 45
              },
              %{
                title: "Cultural Activities",
                description: "Interactive workshops and demonstrations",
                duration: 60
              },
              %{
                title: "Music & Dancing",
                description: "Traditional music and folk dancing",
                duration: 40
              },
              %{
                title: "Closing & Networking",
                description: "Final remarks and networking",
                duration: 15
              }
            ]

          String.contains?(String.downcase(event_title), "festival") ->
            [
              %{
                title: "Opening Ceremony",
                description: "Welcome and festival kickoff",
                duration: 20
              },
              %{
                title: "Morning Activities",
                description: "Games, crafts, and activities for all ages",
                duration: 120
              },
              %{
                title: "Lunch Break",
                description: "Food vendors and picnic areas",
                duration: 60
              },
              %{
                title: "Afternoon Entertainment",
                description: "Live music and performances",
                duration: 150
              },
              %{
                title: "Evening Program",
                description: "Main stage performances",
                duration: 120
              },
              %{
                title: "Closing Celebration",
                description: "Final remarks and fireworks",
                duration: 30
              }
            ]

          String.contains?(String.downcase(event_title), "wine") ->
            [
              %{
                title: "Welcome Reception",
                description: "Registration and welcome wine",
                duration: 20
              },
              %{
                title: "Introduction to Scandinavian Wines",
                description: "Overview of Nordic wine regions",
                duration: 30
              },
              %{
                title: "First Flight Tasting",
                description: "Three white wines with tasting notes",
                duration: 30
              },
              %{
                title: "Second Flight Tasting",
                description: "Three red wines with pairing suggestions",
                duration: 30
              },
              %{
                title: "Cheese & Charcuterie Pairing",
                description: "Small plates paired with wines",
                duration: 40
              },
              %{
                title: "Q&A with Sommelier",
                description: "Questions and final recommendations",
                duration: 20
              }
            ]

          String.contains?(String.downcase(event_title), "hiking") ->
            [
              %{
                title: "Meet & Greet",
                description: "Meet at trailhead, introductions",
                duration: 15
              },
              %{
                title: "Trail Briefing",
                description: "Safety briefing and route overview",
                duration: 10
              },
              %{
                title: "Hike to First Viewpoint",
                description: "Moderate hike with scenic views",
                duration: 90
              },
              %{
                title: "Rest & Snack Break",
                description: "Break time with provided snacks",
                duration: 20
              },
              %{
                title: "Continue to Summit",
                description: "Continue to main viewpoint",
                duration: 60
              },
              %{
                title: "Lunch Break",
                description: "Lunch at scenic location",
                duration: 45
              },
              %{
                title: "Return Hike",
                description: "Return to trailhead",
                duration: 90
              },
              %{
                title: "Closing & Departure",
                description: "Final remarks and departure",
                duration: 10
              }
            ]

          String.contains?(String.downcase(event_title), "language") ->
            [
              %{
                title: "Welcome & Introductions",
                description: "Meet fellow language learners",
                duration: 20
              },
              %{
                title: "Swedish Conversation Circle",
                description: "Practice Swedish with native speakers",
                duration: 30
              },
              %{
                title: "Norwegian Conversation Circle",
                description: "Practice Norwegian with native speakers",
                duration: 30
              },
              %{
                title: "Danish Conversation Circle",
                description: "Practice Danish with native speakers",
                duration: 30
              },
              %{
                title: "Language Exchange Mixer",
                description: "Open conversation time",
                duration: 30
              },
              %{
                title: "Closing & Next Steps",
                description: "Resources and next meeting info",
                duration: 10
              }
            ]

          true ->
            # Generic agenda for other events
            [
              %{
                title: "Welcome & Registration",
                description: "Check-in and welcome",
                duration: 15
              },
              %{
                title: "Opening Remarks",
                description: "Introduction and overview",
                duration: 10
              },
              %{
                title: "Main Program",
                description: "Featured activities and presentations",
                duration: max(30, div(total_minutes - 50, 2))
              },
              %{
                title: "Break",
                description: "Networking and refreshments",
                duration: 15
              },
              %{
                title: "Continued Program",
                description: "Additional activities",
                duration: max(30, div(total_minutes - 50, 2))
              },
              %{
                title: "Closing",
                description: "Final remarks and announcements",
                duration: 10
              }
            ]
        end

      # Convert to time-based agenda items
      current_minute = start_hour * 60 + start_minute

      items
      |> Enum.filter(fn item -> item.duration <= total_minutes end)
      |> Enum.reduce_while({[], current_minute}, fn item, {acc, current} ->
        if current + item.duration <= end_hour * 60 + end_minute do
          item_start_hour = div(current, 60)
          item_start_minute = rem(current, 60)
          item_end_minute = current + item.duration
          item_end_hour = div(item_end_minute, 60)
          item_end_minute = rem(item_end_minute, 60)

          agenda_item = %{
            title: item.title,
            description: item.description,
            start_time: Time.new!(item_start_hour, item_start_minute, 0),
            end_time: Time.new!(item_end_hour, item_end_minute, 0)
          }

          {:cont, {[agenda_item | acc], current + item.duration}}
        else
          {:halt, {acc, current}}
        end
      end)
      |> elem(0)
      |> Enum.reverse()
    end

    # Create example events
    # Mix of free events and events with paid tickets
    event_data = [
      # PAST EVENTS (for testing past events feature)
      %{
        title: "Past Midsummer Celebration 2023",
        description:
          "Our annual midsummer celebration with traditional food and music",
        start_date:
          DateTime.new!(
            Date.new!(2023, 6, 21),
            Time.new!(18, 0, 0),
            "America/Los_Angeles"
          ),
        start_time: ~T[18:00:00],
        end_date:
          DateTime.new!(
            Date.new!(2023, 6, 21),
            Time.new!(22, 0, 0),
            "America/Los_Angeles"
          ),
        end_time: ~T[22:00:00],
        location_name: "Scandinavian Heritage Park",
        address: "456 Heritage St, San Francisco, CA 94103",
        latitude: 37.7849,
        longitude: -122.4094,
        max_attendees: 150,
        ticket_tiers: [
          %{name: "General Admission", type: :free, quantity: 150}
        ]
      },
      %{
        title: "Past Nordic Christmas Dinner",
        description:
          "A festive Christmas dinner featuring traditional Scandinavian cuisine",
        start_date:
          DateTime.new!(
            Date.new!(2023, 12, 15),
            Time.new!(19, 0, 0),
            "America/Los_Angeles"
          ),
        start_time: ~T[19:00:00],
        end_date:
          DateTime.new!(
            Date.new!(2023, 12, 15),
            Time.new!(23, 0, 0),
            "America/Los_Angeles"
          ),
        end_time: ~T[23:00:00],
        location_name: "Grand Scandinavian Hall",
        address: "789 Nordic Blvd, San Francisco, CA 94104",
        latitude: 37.7949,
        longitude: -122.3994,
        max_attendees: 120,
        ticket_tiers: [
          %{
            name: "Member Price",
            type: :paid,
            price: Money.new(65, :USD),
            quantity: 80,
            description: "Discounted for club members"
          },
          %{
            name: "Regular Price",
            type: :paid,
            price: Money.new(85, :USD),
            quantity: 40
          }
        ]
      },
      %{
        title: "Past Fika Social Hour",
        description: "Monthly casual meetup with coffee and pastries",
        start_date:
          DateTime.new!(
            Date.new!(2023, 11, 10),
            Time.new!(14, 0, 0),
            "America/Los_Angeles"
          ),
        start_time: ~T[14:00:00],
        end_date:
          DateTime.new!(
            Date.new!(2023, 11, 10),
            Time.new!(16, 0, 0),
            "America/Los_Angeles"
          ),
        end_time: ~T[16:00:00],
        location_name: "Scandinavian Bakery",
        address: "321 Bakery St, Berkeley, CA 94704",
        latitude: 37.8715,
        longitude: -122.2730,
        max_attendees: 30,
        ticket_tiers: [
          %{name: "Free Coffee & Pastries", type: :free, quantity: 30}
        ]
      },
      %{
        title: "Past Viking History Lecture",
        description: "Educational talk on Viking history and culture",
        start_date:
          DateTime.new!(
            Date.new!(2023, 10, 5),
            Time.new!(18, 30, 0),
            "America/Los_Angeles"
          ),
        start_time: ~T[18:30:00],
        end_date:
          DateTime.new!(
            Date.new!(2023, 10, 5),
            Time.new!(20, 30, 0),
            "America/Los_Angeles"
          ),
        end_time: ~T[20:30:00],
        location_name: "Community Library",
        address: "555 Library Ave, San Francisco, CA 94105",
        latitude: 37.7649,
        longitude: -122.4294,
        max_attendees: 40,
        ticket_tiers: [
          %{name: "Free Admission", type: :free, quantity: 40}
        ]
      },

      # UPCOMING EVENTS (existing ones)
      # Free events
      %{
        title: "Scandinavian Cultural Evening",
        description:
          "Join us for an evening of Scandinavian culture, food, and music",
        start_date: DateTime.add(DateTime.utc_now(), 30, :day),
        start_time: ~T[18:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 30, :day),
        end_time: ~T[22:00:00],
        location_name: "Scandinavian Community Center",
        address: "123 Main St, San Francisco, CA 94102",
        latitude: 37.7749,
        longitude: -122.4194,
        max_attendees: 100,
        ticket_tiers: [
          %{name: "General Admission", type: :free, quantity: 100}
        ]
      },
      %{
        title: "Nordic Book Discussion",
        description: "Monthly book club meeting discussing Nordic literature",
        start_date: DateTime.add(DateTime.utc_now(), 45, :day),
        start_time: ~T[19:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 45, :day),
        end_time: ~T[21:00:00],
        location_name: "Public Library",
        address: "456 Library Ave, San Francisco, CA 94103",
        latitude: 37.7849,
        longitude: -122.4094,
        max_attendees: 25,
        ticket_tiers: [
          %{name: "Member Admission", type: :free, quantity: 25}
        ]
      },
      # Paid events
      %{
        title: "Scandinavian Gala Dinner",
        description:
          "Elegant dinner featuring traditional Scandinavian cuisine",
        start_date: DateTime.add(DateTime.utc_now(), 60, :day),
        start_time: ~T[19:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 60, :day),
        end_time: ~T[23:00:00],
        location_name: "Grand Ballroom",
        address: "789 Event Blvd, San Francisco, CA 94104",
        latitude: 37.7949,
        longitude: -122.3994,
        max_attendees: 150,
        ticket_tiers: [
          %{
            name: "Early Bird",
            type: :paid,
            price: Money.new(75, :USD),
            quantity: 50,
            description: "Save $25!"
          },
          %{
            name: "Regular Ticket",
            type: :paid,
            price: Money.new(100, :USD),
            quantity: 100
          }
        ]
      },
      %{
        title: "Wine Tasting: Scandinavian Varietals",
        description:
          "Sample wines from Scandinavian producers with expert sommeliers",
        start_date: DateTime.add(DateTime.utc_now(), 75, :day),
        start_time: ~T[17:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 75, :day),
        end_time: ~T[20:00:00],
        location_name: "Wine Cellar",
        address: "321 Vineyard St, Napa, CA 94558",
        latitude: 38.2975,
        longitude: -122.2869,
        max_attendees: 40,
        ticket_tiers: [
          %{
            name: "Member Price",
            type: :paid,
            price: Money.new(45, :USD),
            quantity: 20
          },
          %{
            name: "Non-Member Price",
            type: :paid,
            price: Money.new(60, :USD),
            quantity: 20
          }
        ]
      },
      # Events with both free and paid tiers
      %{
        title: "Summer Festival 2024",
        description:
          "Our biggest event of the year! Music, food, games, and more",
        start_date: DateTime.add(DateTime.utc_now(), 90, :day),
        start_time: ~T[10:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 90, :day),
        end_time: ~T[22:00:00],
        location_name: "Golden Gate Park",
        address: "1000 Park Blvd, San Francisco, CA 94117",
        latitude: 37.7694,
        longitude: -122.4862,
        max_attendees: 500,
        ticket_tiers: [
          %{
            name: "Free Admission",
            type: :free,
            quantity: 300,
            description: "General admission to the festival"
          },
          %{
            name: "VIP Pass",
            type: :paid,
            price: Money.new(150, :USD),
            quantity: 100,
            description: "Includes VIP area access and premium food"
          },
          %{
            name: "Family Pack",
            type: :paid,
            price: Money.new(200, :USD),
            quantity: 50,
            description: "Up to 4 people"
          }
        ]
      },
      %{
        title: "Hiking Day Trip: Marin Headlands",
        description: "Guided hiking trip with picnic lunch included",
        start_date: DateTime.add(DateTime.utc_now(), 50, :day),
        start_time: ~T[08:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 50, :day),
        end_time: ~T[18:00:00],
        location_name: "Marin Headlands Trailhead",
        address: "Marin Headlands, Sausalito, CA 94965",
        latitude: 37.8267,
        longitude: -122.4991,
        max_attendees: 30,
        ticket_tiers: [
          %{name: "Free (Bring Your Own Lunch)", type: :free, quantity: 15},
          %{
            name: "With Lunch",
            type: :paid,
            price: Money.new(25, :USD),
            quantity: 15,
            description: "Includes catered picnic lunch"
          }
        ]
      },
      # Another free event
      %{
        title: "Language Exchange Meetup",
        description:
          "Practice your Scandinavian languages with native speakers",
        start_date: DateTime.add(DateTime.utc_now(), 20, :day),
        start_time: ~T[18:30:00],
        end_date: DateTime.add(DateTime.utc_now(), 20, :day),
        end_time: ~T[20:30:00],
        location_name: "Community Center",
        address: "555 Community Way, Berkeley, CA 94704",
        latitude: 37.8715,
        longitude: -122.2730,
        max_attendees: 50,
        ticket_tiers: [
          %{name: "Free Admission", type: :free, quantity: 50}
        ]
      }
    ]

    Enum.each(event_data, fn event_attrs ->
      try do
        # Check if event already exists by title
        existing_event =
          Repo.one(
            from e in Event, where: e.title == ^event_attrs.title, limit: 1
          )

        if existing_event do
          IO.puts("Event already exists, skipping: #{event_attrs.title}")

          # Still try to create agenda if it doesn't exist
          try do
            existing_agendas = Agendas.list_agendas_for_event(existing_event.id)

            if length(existing_agendas) == 0 do
              # Use existing event's times if available, fallback to event_attrs
              start_time = existing_event.start_time || event_attrs.start_time
              end_time = existing_event.end_time || event_attrs.end_time

              agenda_items =
                generate_agenda_items.(
                  existing_event.title,
                  start_time,
                  end_time
                )

              if length(agenda_items) > 0 do
                case Agendas.create_agenda(existing_event, %{
                       title: "Event Agenda"
                     }) do
                  {:ok, agenda} ->
                    items_created =
                      Enum.reduce(agenda_items, 0, fn item_attrs, count ->
                        case Agendas.create_agenda_item(
                               existing_event.id,
                               agenda,
                               item_attrs
                             ) do
                          {:ok, _agenda_item} ->
                            count + 1

                          {:error, changeset} ->
                            IO.puts(
                              "  Failed to create agenda item '#{item_attrs.title}': #{inspect(changeset.errors)}"
                            )

                            count
                        end
                      end)

                    IO.puts(
                      "  Created agenda with #{items_created} agenda item(s) for existing event '#{existing_event.title}'"
                    )

                  {:error, changeset} ->
                    IO.puts(
                      "  Failed to create agenda for existing event '#{existing_event.title}': #{inspect(changeset.errors)}"
                    )
                end
              end
            end
          rescue
            e ->
              IO.puts(
                "  Error creating agenda for existing event '#{existing_event.title}': #{inspect(e)}"
              )
          end
        else
          # Use admin_user for event creation since it requires admin role
          organizer = admin_user
          image = Enum.random(uploaded_images)

          # Calculate publish_at (before start_date)
          publish_at = DateTime.add(event_attrs.start_date, -7, :day)

          case Events.create_event(%{
                 state: "published",
                 organizer_id: organizer.id,
                 title: event_attrs.title,
                 description: event_attrs.description,
                 image_id: image.id,
                 start_date: event_attrs.start_date,
                 start_time: event_attrs.start_time,
                 end_date: event_attrs.end_date,
                 end_time: event_attrs.end_time,
                 location_name: event_attrs.location_name,
                 address: event_attrs.address,
                 latitude: event_attrs.latitude,
                 longitude: event_attrs.longitude,
                 max_attendees: event_attrs.max_attendees,
                 unlimited_capacity: false,
                 published_at: publish_at,
                 publish_at: publish_at,
                 raw_details: """
                 <p>A wonderful serenity has taken possession of my entire soul, like these sweet mornings of spring which I enjoy with my whole heart. I am alone, and feel the charm of existence in this spot, which was created for the bliss of souls like mine.</p>
                 <p>I am so happy, my dear friend, so absorbed in the exquisite sense of mere tranquil existence, that I neglect my talents. I should be incapable of drawing a single stroke at the present moment; and yet I feel that I never was a greater artist than now.</p>
                 <p>When, while the lovely valley teems with vapour around me, and the meridian sun strikes the upper surface of the impenetrable foliage of my trees, and but a few stray gleams steal into the inner sanctuary, I throw myself down among the tall grass by the trickling stream; and, as I lie close to the earth, a thousand unknown plants are noticed by me: when I hear the buzz of the little world among the stalks, and grow familiar with the countless indescribable forms of the insects and flies, then I feel the presence of the Almighty, who formed us in his own image, and the breath</p>
                 <p>We hope to see you there!</p>
                 """,
                 rendered_details: """
                 <p>A wonderful serenity has taken possession of my entire soul, like these sweet mornings of spring which I enjoy with my whole heart. I am alone, and feel the charm of existence in this spot, which was created for the bliss of souls like mine.</p>
                 <p>I am so happy, my dear friend, so absorbed in the exquisite sense of mere tranquil existence, that I neglect my talents. I should be incapable of drawing a single stroke at the present moment; and yet I feel that I never was a greater artist than now.</p>
                 <p>When, while the lovely valley teems with vapour around me, and the meridian sun strikes the upper surface of the impenetrable foliage of my trees, and but a few stray gleams steal into the inner sanctuary, I throw myself down among the tall grass by the trickling stream; and, as I lie close to the earth, a thousand unknown plants are noticed by me: when I hear the buzz of the little world among the stalks, and grow familiar with the countless indescribable forms of the insects and flies, then I feel the presence of the Almighty, who formed us in his own image, and the breath</p>
                 <p>We hope to see you there!</p>
                 """
               }) do
            {:ok, event} ->
              # Create ticket tiers for the event
              Enum.each(event_attrs.ticket_tiers, fn tier_attrs ->
                tier_name = tier_attrs.name

                # Check if ticket tier already exists for this event
                existing_tier =
                  Repo.one(
                    from tt in Ysc.Events.TicketTier,
                      where: tt.event_id == ^event.id and tt.name == ^tier_name,
                      limit: 1
                  )

                if existing_tier do
                  IO.puts(
                    "Ticket tier '#{tier_name}' already exists for event '#{event.title}', skipping"
                  )
                else
                  case Events.create_ticket_tier(
                         Map.merge(tier_attrs, %{event_id: event.id})
                       ) do
                    {:ok, _tier} ->
                      :ok

                    {:error, changeset} ->
                      IO.puts(
                        "Failed to create ticket tier '#{tier_name}': #{inspect(changeset.errors)}"
                      )
                  end
                end
              end)

              # Create agenda with agenda items
              try do
                # Check if agenda already exists for this event
                existing_agendas = Agendas.list_agendas_for_event(event.id)

                if length(existing_agendas) > 0 do
                  IO.puts(
                    "  Agenda already exists for '#{event.title}', skipping"
                  )
                else
                  # Generate agenda items based on event type
                  agenda_items =
                    generate_agenda_items.(
                      event.title,
                      event_attrs.start_time,
                      event_attrs.end_time
                    )

                  if length(agenda_items) > 0 do
                    # Create the agenda
                    case Agendas.create_agenda(event, %{title: "Event Agenda"}) do
                      {:ok, agenda} ->
                        # Create agenda items
                        items_created =
                          Enum.reduce(agenda_items, 0, fn item_attrs, count ->
                            case Agendas.create_agenda_item(
                                   event.id,
                                   agenda,
                                   item_attrs
                                 ) do
                              {:ok, _agenda_item} ->
                                count + 1

                              {:error, changeset} ->
                                IO.puts(
                                  "  Failed to create agenda item '#{item_attrs.title}': #{inspect(changeset.errors)}"
                                )

                                count
                            end
                          end)

                        IO.puts(
                          "  Created agenda with #{items_created} agenda item(s) for '#{event.title}'"
                        )

                      {:error, changeset} ->
                        IO.puts(
                          "  Failed to create agenda for '#{event.title}': #{inspect(changeset.errors)}"
                        )
                    end
                  else
                    IO.puts(
                      "  No agenda items generated for '#{event.title}' (event too short)"
                    )
                  end
                end
              rescue
                e ->
                  IO.puts(
                    "  Error creating agenda for '#{event.title}': #{inspect(e)}"
                  )
              end

              IO.puts(
                "Created event: #{event.title} (#{length(event_attrs.ticket_tiers)} ticket tier(s))"
              )

            {:error, changeset} ->
              IO.puts(
                "Failed to create event: #{event_attrs.title} - #{inspect(changeset.errors)}"
              )
          end
        end
      rescue
        e ->
          IO.puts("Error creating event '#{event_attrs.title}': #{inspect(e)}")
      end
    end)

    IO.puts("\n✅ Seed completed successfully!")
    IO.puts("   - #{length(uploaded_images)} images uploaded to S3")
    IO.puts("   - Posts and events checked/created")
  else
    IO.puts(
      "⚠️  No images found in #{seed_assets_dir}. Skipping posts and events creation."
    )
  end
else
  IO.puts(
    "⚠️  No active users found. Please create users first before seeding posts and events."
  )
end

# Seed room images for Tahoe rooms
IO.puts("\n🖼️  Seeding room images for Tahoe rooms...")

alias Ysc.Bookings.{Room, RoomCategory, Season}
import Ecto.Query

# Get all Tahoe rooms
tahoe_rooms =
  Repo.all(from r in Room, where: r.property == :tahoe and r.is_active == true)

IO.puts("  Found #{length(tahoe_rooms)} Tahoe rooms to process")

# If no rooms exist, create them (with minimal dependencies)
if length(tahoe_rooms) == 0 do
  IO.puts("  ⚠️  No Tahoe rooms found. Creating rooms and dependencies...")

  # Create room categories if they don't exist
  single_category =
    Repo.get_by(RoomCategory, name: "single") ||
      Repo.insert!(
        RoomCategory.changeset(%RoomCategory{}, %{
          name: "single",
          notes: "Single bed rooms (max 1 person)"
        })
      )

  standard_category =
    Repo.get_by(RoomCategory, name: "standard") ||
      Repo.insert!(
        RoomCategory.changeset(%RoomCategory{}, %{
          name: "standard",
          notes: "Standard rooms"
        })
      )

  family_category =
    Repo.get_by(RoomCategory, name: "family") ||
      Repo.insert!(
        RoomCategory.changeset(%RoomCategory{}, %{
          name: "family",
          notes: "Family rooms (2 person minimum)"
        })
      )

  # Create summer season for Tahoe if it doesn't exist
  base_year = 2024
  summer_start = Date.new!(base_year, 5, 1)
  summer_end = Date.new!(base_year, 10, 31)

  tahoe_summer =
    Repo.get_by(Season, name: "Summer", property: :tahoe) ||
      Repo.insert!(
        Season.changeset(%Season{}, %{
          name: "Summer",
          description:
            "Summer season for Tahoe cabin (May 1 - Oct 31, recurring annually)",
          property: :tahoe,
          start_date: summer_start,
          end_date: summer_end,
          is_default: true,
          advance_booking_days: nil
        })
      )

  # Create rooms
  room_names = [
    "Room 1",
    "Room 2",
    "Room 3",
    "Room 4",
    "Room 5a",
    "Room 5b",
    "Room 6",
    "Room 7"
  ]

  tahoe_rooms =
    Enum.map(room_names, fn name ->
      room_attrs =
        cond do
          name == "Room 5a" ->
            %{
              name: name,
              description:
                "Cozy single bed room with 1 single bed. Perfect for solo travelers.",
              property: :tahoe,
              capacity_max: 1,
              min_billable_occupancy: 1,
              is_single_bed: true,
              single_beds: 1,
              queen_beds: 0,
              king_beds: 0,
              is_active: true,
              room_category_id: single_category.id,
              default_season_id: tahoe_summer.id
            }

          name == "Room 5b" ->
            %{
              name: name,
              description:
                "Cozy single bed room with 1 single bed. Perfect for solo travelers.",
              property: :tahoe,
              capacity_max: 1,
              min_billable_occupancy: 1,
              is_single_bed: true,
              single_beds: 1,
              queen_beds: 0,
              king_beds: 0,
              is_active: true,
              room_category_id: single_category.id,
              default_season_id: tahoe_summer.id
            }

          name == "Room 4" ->
            %{
              name: name,
              description:
                "Spacious family room with 1 queen bed and 3 single beds. Accommodates up to 5 guests. Minimum 2 guests required.",
              property: :tahoe,
              capacity_max: 5,
              min_billable_occupancy: 2,
              is_single_bed: false,
              single_beds: 3,
              queen_beds: 1,
              king_beds: 0,
              is_active: true,
              room_category_id: family_category.id,
              default_season_id: tahoe_summer.id
            }

          name == "Room 1" ->
            %{
              name: name,
              description:
                "Comfortable room with 2 single beds. Perfect for two guests.",
              property: :tahoe,
              capacity_max: 2,
              min_billable_occupancy: 1,
              is_single_bed: false,
              single_beds: 2,
              queen_beds: 0,
              king_beds: 0,
              is_active: true,
              room_category_id: standard_category.id,
              default_season_id: tahoe_summer.id
            }

          name == "Room 2" ->
            %{
              name: name,
              description:
                "Comfortable room with 1 queen bed. Ideal for couples or two guests.",
              property: :tahoe,
              capacity_max: 2,
              min_billable_occupancy: 1,
              is_single_bed: false,
              single_beds: 0,
              queen_beds: 1,
              king_beds: 0,
              is_active: true,
              room_category_id: standard_category.id,
              default_season_id: tahoe_summer.id
            }

          name == "Room 3" ->
            %{
              name: name,
              description:
                "Comfortable room with 1 queen bed. Ideal for couples or two guests.",
              property: :tahoe,
              capacity_max: 2,
              min_billable_occupancy: 1,
              is_single_bed: false,
              single_beds: 0,
              queen_beds: 1,
              king_beds: 0,
              is_active: true,
              room_category_id: standard_category.id,
              default_season_id: tahoe_summer.id
            }

          name == "Room 6" ->
            %{
              name: name,
              description:
                "Spacious room with 1 queen bed and 1 single bed. Accommodates up to 3 guests.",
              property: :tahoe,
              capacity_max: 3,
              min_billable_occupancy: 1,
              is_single_bed: false,
              single_beds: 1,
              queen_beds: 1,
              king_beds: 0,
              is_active: true,
              room_category_id: standard_category.id,
              default_season_id: tahoe_summer.id
            }

          name == "Room 7" ->
            %{
              name: name,
              description:
                "Comfortable room with 1 queen bed. Ideal for couples or two guests.",
              property: :tahoe,
              capacity_max: 2,
              min_billable_occupancy: 1,
              is_single_bed: false,
              single_beds: 0,
              queen_beds: 1,
              king_beds: 0,
              is_active: true,
              room_category_id: standard_category.id,
              default_season_id: tahoe_summer.id
            }

          true ->
            %{
              name: name,
              description: "Standard room",
              property: :tahoe,
              capacity_max: 2,
              min_billable_occupancy: 1,
              is_single_bed: false,
              single_beds: 0,
              queen_beds: 0,
              king_beds: 0,
              is_active: true,
              room_category_id: standard_category.id,
              default_season_id: tahoe_summer.id
            }
        end

      # Get or create room
      case Repo.get_by(Room, name: name, property: :tahoe) do
        nil ->
          Repo.insert!(Room.changeset(%Room{}, room_attrs))

        existing ->
          existing
      end
    end)

  IO.puts("  ✅ Created #{length(tahoe_rooms)} Tahoe rooms")
end

# Re-fetch rooms after potential creation
tahoe_rooms =
  Repo.all(from r in Room, where: r.property == :tahoe and r.is_active == true)

if length(tahoe_rooms) > 0 do
  # Directory containing room images
  tahoe_images_dir =
    Path.join([File.cwd!(), "priv", "static", "images", "tahoe"])

  if File.exists?(tahoe_images_dir) do
    # Map room names to image filenames
    # Room 1 -> tahoe_room_1.jpg, Room 2 -> tahoe_room_2.jpg, etc.
    # Room 5a and 5b share the same image (tahoe_room_5.jpg)
    room_image_map = %{
      "Room 1" => "tahoe_room_1.jpg",
      "Room 2" => "tahoe_room_2.jpg",
      "Room 3" => "tahoe_room_3.jpg",
      "Room 4" => "tahoe_room_4.jpg",
      "Room 5a" => "tahoe_room_5.jpg",
      "Room 5b" => "tahoe_room_5.jpg",
      "Room 6" => "tahoe_room_6.jpg",
      "Room 7" => "tahoe_room_7.jpg"
    }

    images_created = 0
    images_associated = 0

    {images_created, images_associated} =
      Enum.reduce(tahoe_rooms, {0, 0}, fn room, {created_acc, associated_acc} ->
        image_filename = Map.get(room_image_map, room.name)

        if image_filename do
          image_path = Path.join(tahoe_images_dir, image_filename)

          if File.exists?(image_path) do
            image_title = "Tahoe #{room.name}"

            # Check if image already exists by title
            existing_image =
              Repo.one(
                from i in Image,
                  where: i.title == ^image_title,
                  limit: 1
              )

            {room_image, was_new_image} =
              if existing_image do
                IO.puts(
                  "  Image already exists for #{room.name}, associating with room..."
                )

                {existing_image, false}
              else
                # Upload raw file to S3
                upload_result =
                  try do
                    Media.upload_file_to_s3(image_path)
                  rescue
                    e ->
                      IO.puts(
                        "  Failed to upload #{image_filename} to S3: #{inspect(e)}"
                      )

                      nil
                  end

                if upload_result do
                  raw_s3_path = upload_result[:body][:location]

                  # Check if image with this raw_image_path already exists
                  existing_by_path =
                    Repo.one(
                      from i in Image,
                        where: i.raw_image_path == ^URI.encode(raw_s3_path),
                        limit: 1
                    )

                  if existing_by_path do
                    IO.puts(
                      "  Image with path already exists for #{room.name}, using existing..."
                    )

                    {existing_by_path, false}
                  else
                    # Create image record (must use admin_user for authorization)
                    case Media.add_new_image(
                           %{
                             raw_image_path: URI.encode(raw_s3_path),
                             user_id: admin_user.id,
                             title: image_title,
                             processing_state: "unprocessed"
                           },
                           admin_user
                         ) do
                      {:ok, new_image} ->
                        IO.puts(
                          "  ✅ Created image record for #{room.name} (id: #{new_image.id})"
                        )

                        # Process the image (create thumbnails, optimized versions, blur hash)
                        temp_dir = "/tmp/image_processor"
                        File.mkdir_p!(temp_dir)
                        tmp_output_file = "#{temp_dir}/#{new_image.id}"
                        optimized_output_path = "#{tmp_output_file}_optimized"
                        thumbnail_output_path = "#{tmp_output_file}_thumb"

                        processed_image =
                          try do
                            Media.process_image_upload(
                              new_image,
                              image_path,
                              thumbnail_output_path,
                              optimized_output_path
                            )
                          rescue
                            e ->
                              IO.puts(
                                "  Failed to process image #{image_filename}: #{inspect(e)}"
                              )

                              new_image
                          end

                        # Clean up temp files
                        try do
                          File.rm(tmp_output_file)

                          ["_optimized", "_thumb"]
                          |> Enum.each(fn suffix ->
                            [".jpg", ".jpeg", ".png", ".webp"]
                            |> Enum.each(fn ext ->
                              path = "#{tmp_output_file}#{suffix}#{ext}"
                              if File.exists?(path), do: File.rm(path)
                            end)
                          end)

                          File.rmdir(temp_dir)
                        rescue
                          _ -> :ok
                        end

                        {processed_image, true}

                      {:error, reason} ->
                        IO.puts(
                          "  ❌ Failed to create image record for #{image_filename}: #{inspect(reason)}"
                        )

                        {nil, false}
                    end
                  end
                else
                  {nil, false}
                end
              end

            if room_image do
              # Reload room from database to get fresh data
              fresh_room = Repo.get!(Room, room.id)

              # Update room with image_id using Room changeset
              result =
                fresh_room
                |> Room.changeset(%{image_id: room_image.id})
                |> Repo.update()

              case result do
                {:ok, updated_room} ->
                  IO.puts(
                    "  ✅ Associated image with #{room.name} (image_id: #{updated_room.image_id})"
                  )

                  {created_acc + if(was_new_image, do: 1, else: 0),
                   associated_acc + 1}

                {:error, changeset} ->
                  IO.puts(
                    "  ❌ Failed to update #{room.name} with image: #{inspect(changeset.errors)}"
                  )

                  {created_acc + if(was_new_image, do: 1, else: 0),
                   associated_acc}
              end
            else
              IO.puts("  ⚠️  Could not create/retrieve image for #{room.name}")
              {created_acc, associated_acc}
            end
          else
            IO.puts("  ⚠️  Image file not found: #{image_filename}")
            {created_acc, associated_acc}
          end
        else
          IO.puts("  ℹ️  No image mapping for #{room.name}, skipping")
          {created_acc, associated_acc}
        end
      end)

    IO.puts("\n✅ Room images seeding completed!")
    IO.puts("   - Images created: #{images_created}")
    IO.puts("   - Images associated with rooms: #{images_associated}")
    IO.puts("   - Total images in database: #{Media.count_images()}")
  else
    IO.puts("⚠️  Tahoe images directory not found: #{tahoe_images_dir}")
  end
else
  IO.puts(
    "⚠️  No Tahoe rooms found. Please run seeds_bookings.exs first to create rooms."
  )
end

# Seed refund policies for Tahoe property
IO.puts("\n📋 Seeding refund policies...")

# Tahoe Full Cabin (Buyout) Policy
tahoe_buyout_policy =
  case Bookings.get_active_refund_policy(:tahoe, :buyout) do
    nil ->
      policy =
        Bookings.create_refund_policy!(%{
          name: "Tahoe Full Cabin Cancellation Policy",
          description:
            "Cancellation policy for full cabin (buyout) bookings at Tahoe property",
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true
        })

      policy

    existing_policy ->
      IO.puts("  ⚠️  Tahoe buyout policy already exists, skipping creation")
      existing_policy
  end

# Create rules for Tahoe buyout policy
if tahoe_buyout_policy do
  # Rule 1: Less than 14 days = 0% refund (100% forfeiture)
  case Bookings.list_refund_policy_rules(tahoe_buyout_policy.id)
       |> Enum.find(fn r -> r.days_before_checkin == 14 end) do
    nil ->
      Bookings.create_refund_policy_rule!(%{
        refund_policy_id: tahoe_buyout_policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("0"),
        description:
          "Reservations cancelled less than 14 days prior to date of arrival will result in forfeiture of 100% of the cost",
        priority: 0
      })

    _ ->
      :ok
  end

  # Rule 2: Less than 21 days = 50% refund (50% forfeiture)
  case Bookings.list_refund_policy_rules(tahoe_buyout_policy.id)
       |> Enum.find(fn r -> r.days_before_checkin == 21 end) do
    nil ->
      Bookings.create_refund_policy_rule!(%{
        refund_policy_id: tahoe_buyout_policy.id,
        days_before_checkin: 21,
        refund_percentage: Decimal.new("50"),
        description:
          "Reservations cancelled less than 21 days prior to date of arrival are subject to forfeiture of 50% of the cost",
        priority: 0
      })

    _ ->
      :ok
  end

  IO.puts("  ✅ Tahoe Full Cabin (Buyout) refund policy seeded")
end

# Tahoe Rooms Policy
tahoe_room_policy =
  case Bookings.get_active_refund_policy(:tahoe, :room) do
    nil ->
      policy =
        Bookings.create_refund_policy!(%{
          name: "Tahoe Rooms Cancellation Policy",
          description:
            "Cancellation policy for room bookings at Tahoe property",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      policy

    existing_policy ->
      IO.puts("  ⚠️  Tahoe room policy already exists, skipping creation")
      existing_policy
  end

# Create rules for Tahoe room policy
if tahoe_room_policy do
  # Rule 1: Less than 7 days = 0% refund (100% forfeiture)
  case Bookings.list_refund_policy_rules(tahoe_room_policy.id)
       |> Enum.find(fn r -> r.days_before_checkin == 7 end) do
    nil ->
      Bookings.create_refund_policy_rule!(%{
        refund_policy_id: tahoe_room_policy.id,
        days_before_checkin: 7,
        refund_percentage: Decimal.new("0"),
        description:
          "Reservations cancelled less than 7 days prior to date of arrival will result in forfeiture of 100% of the cost",
        priority: 0
      })

    _ ->
      :ok
  end

  # Rule 2: Less than 14 days = 50% refund (50% forfeiture)
  case Bookings.list_refund_policy_rules(tahoe_room_policy.id)
       |> Enum.find(fn r -> r.days_before_checkin == 14 end) do
    nil ->
      Bookings.create_refund_policy_rule!(%{
        refund_policy_id: tahoe_room_policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("50"),
        description:
          "Reservations cancelled less than 14 days prior to date of arrival are subject to forfeiture of 50% of the cost",
        priority: 0
      })

    _ ->
      :ok
  end

  IO.puts("  ✅ Tahoe Rooms refund policy seeded")
end

IO.puts("✅ Refund policies seeding completed!")
