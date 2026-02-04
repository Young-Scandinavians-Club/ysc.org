# Production seeding script
# Run with: mix run priv/repo/seeds_prod.exs
#
# This script seeds essential data for production:
# - SiteSettings (Instagram and Facebook)
# - Admin user for login
# - Default seasons for Tahoe cabin (Winter and Summer)
# - Default seasons for Clear Lake cabin (Winter and Summer)
# - Room categories (single, standard, family)
# - Rooms for Tahoe and Clear Lake properties
# - Default pricing rules for all booking modes
# - Default refund policies and rules

alias Ysc.Repo
alias Ysc.Accounts.User
alias Ysc.SiteSettings.SiteSetting
alias Ysc.Bookings.{Season, RoomCategory, Room, PricingRule}
alias Ysc.Bookings
alias Money

IO.puts("🌱 Starting production seed...")

# 1. Seed SiteSettings
IO.puts("📝 Seeding SiteSettings...")

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

IO.puts("  ✅ SiteSettings seeded")

# 2. Create admin user
IO.puts("👤 Creating admin user...")

admin_user =
  case Repo.get_by(User, email: "admin@ysc.org") do
    nil ->
      admin_changeset =
        User.registration_changeset(%User{}, %{
          email: "admin@ysc.org",
          password: System.get_env("ADMIN_PASSWORD") || "change_me_in_production",
          role: :admin,
          state: :active,
          first_name: "Admin",
          last_name: "User",
          phone_number: "+14159009009",
          most_connected_country: "SE",
          confirmed_at: DateTime.utc_now(),
          email_verified_at: DateTime.utc_now(),
          phone_verified_at: DateTime.utc_now(),
          date_of_birth: ~D[1980-01-15],
          registration_form: %{
            membership_type: "family",
            membership_eligibility: ["citizen_of_scandinavia", "born_in_scandinavia"],
            occupation: "Administrator",
            birth_date: "1980-01-15",
            address: "123 Admin St",
            country: "USA",
            city: "San Francisco",
            region: "CA",
            postal_code: "94102",
            place_of_birth: "Sweden",
            citizenship: "USA",
            most_connected_nordic_country: "Sweden",
            link_to_scandinavia: "Administrative role",
            lived_in_scandinavia: "Yes",
            spoken_languages: "English, Swedish",
            hear_about_the_club: "Administrative setup",
            agreed_to_bylaws: "true",
            agreed_to_bylaws_at: DateTime.utc_now(),
            started: DateTime.utc_now(),
            completed: DateTime.utc_now(),
            browser_timezone: "America/Los_Angeles"
          }
        })

      case Repo.insert(admin_changeset, on_conflict: :nothing) do
        {:ok, user} when not is_nil(user) ->
          IO.puts("  ✅ Admin user created: admin@ysc.org")
          user

        {:ok, nil} ->
          # Conflict occurred, fetch the existing user
          existing = Repo.get_by!(User, email: "admin@ysc.org")
          # Ensure email and phone are verified for existing admin user
          updated =
            existing
            |> User.registration_changeset(%{
              email_verified_at: existing.email_verified_at || DateTime.utc_now(),
              phone_verified_at: existing.phone_verified_at || DateTime.utc_now()
            }, hash_password: false, validate_email: false)
            |> Repo.update!()
          IO.puts("  ℹ️  Admin user already exists: admin@ysc.org")
          updated

        {:error, changeset} ->
          # If insert fails, try to fetch again (might have been created by another process)
          existing = Repo.get_by(User, email: "admin@ysc.org")
          if existing do
            # Ensure email and phone are verified for existing admin user
            updated =
              existing
              |> User.registration_changeset(%{
                email_verified_at: existing.email_verified_at || DateTime.utc_now(),
                phone_verified_at: existing.phone_verified_at || DateTime.utc_now()
              }, hash_password: false, validate_email: false)
              |> Repo.update!()
            IO.puts("  ℹ️  Admin user already exists: admin@ysc.org")
            updated
          else
            IO.puts("  ❌ Failed to create admin user: #{inspect(changeset.errors)}")
            raise("Failed to create or find admin user")
          end
      end

    existing_user ->
      IO.puts("  ℹ️  Admin user already exists: admin@ysc.org")
      existing_user
  end

# 3. Create seasons for Tahoe cabin
IO.puts("🏔️  Creating seasons for Tahoe cabin...")

# Seasons are recurring annually - we use a base year for the dates, but they repeat every year
# Winter: Nov 1 to April 30 (spans years - recurring pattern)
# Summer: May 1 to October 31 (same year - recurring pattern)
base_year = 2024

# Winter season: Nov 1 to April 30 (year-spanning, recurs annually)
winter_start = Date.new!(base_year, 11, 1)
winter_end = Date.new!(base_year + 1, 4, 30)

# Summer season: May 1 to October 31 (same year, recurs annually)
summer_start = Date.new!(base_year, 5, 1)
summer_end = Date.new!(base_year, 10, 31)

# Tahoe Winter season
tahoe_winter =
  case Repo.get_by(Season, name: "Winter", property: :tahoe) do
    nil ->
      season =
        Season.changeset(%Season{}, %{
          name: "Winter",
          description: "Winter season for Tahoe cabin (Nov 1 - Apr 30, recurring annually)",
          property: :tahoe,
          start_date: winter_start,
          end_date: winter_end,
          is_default: false,
          advance_booking_days: 45,
          max_nights: 4
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created Tahoe Winter season")
      season

    existing ->
      IO.puts("  ℹ️  Tahoe Winter season already exists")
      existing
  end

# Tahoe Summer season
tahoe_summer =
  case Repo.get_by(Season, name: "Summer", property: :tahoe) do
    nil ->
      season =
        Season.changeset(%Season{}, %{
          name: "Summer",
          description: "Summer season for Tahoe cabin (May 1 - Oct 31, recurring annually)",
          property: :tahoe,
          start_date: summer_start,
          end_date: summer_end,
          is_default: true,
          advance_booking_days: nil,
          max_nights: 4
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created Tahoe Summer season")
      season

    existing ->
      IO.puts("  ℹ️  Tahoe Summer season already exists")
      existing
  end

# 4. Create seasons for Clear Lake cabin
IO.puts("🏞️  Creating seasons for Clear Lake cabin...")

# Clear Lake Winter season
clear_lake_winter =
  case Repo.get_by(Season, name: "Winter", property: :clear_lake) do
    nil ->
      season =
        Season.changeset(%Season{}, %{
          name: "Winter",
          description: "Winter season for Clear Lake cabin (Nov 1 - Apr 30, recurring annually)",
          property: :clear_lake,
          start_date: winter_start,
          end_date: winter_end,
          is_default: false,
          advance_booking_days: nil,
          max_nights: 30
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created Clear Lake Winter season")
      season

    existing ->
      IO.puts("  ℹ️  Clear Lake Winter season already exists")
      existing
  end

# Clear Lake Summer season
clear_lake_summer =
  case Repo.get_by(Season, name: "Summer", property: :clear_lake) do
    nil ->
      season =
        Season.changeset(%Season{}, %{
          name: "Summer",
          description: "Summer season for Clear Lake cabin (May 1 - Oct 31, recurring annually)",
          property: :clear_lake,
          start_date: summer_start,
          end_date: summer_end,
          is_default: true,
          advance_booking_days: nil,
          max_nights: 30
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created Clear Lake Summer season")
      season

    existing ->
      IO.puts("  ℹ️  Clear Lake Summer season already exists")
      existing
  end

# 5. Create room categories
IO.puts("🏷️  Creating room categories...")

single_category =
  case Repo.get_by(RoomCategory, name: "single") do
    nil ->
      category =
        RoomCategory.changeset(%RoomCategory{}, %{
          name: "single",
          notes: "Single bed rooms (max 1 person)"
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created single category")
      category

    existing ->
      IO.puts("  ℹ️  Single category already exists")
      existing
  end

standard_category =
  case Repo.get_by(RoomCategory, name: "standard") do
    nil ->
      category =
        RoomCategory.changeset(%RoomCategory{}, %{
          name: "standard",
          notes: "Standard rooms"
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created standard category")
      category

    existing ->
      IO.puts("  ℹ️  Standard category already exists")
      existing
  end

family_category =
  case Repo.get_by(RoomCategory, name: "family") do
    nil ->
      category =
        RoomCategory.changeset(%RoomCategory{}, %{
          name: "family",
          notes: "Family rooms (2 person minimum)"
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created family category")
      category

    existing ->
      IO.puts("  ℹ️  Family category already exists")
      existing
  end

# 6. Create Tahoe rooms
IO.puts("🏔️  Creating Tahoe rooms...")

room_names = ["Room 1", "Room 2", "Room 3", "Room 4", "Room 5a", "Room 5b", "Room 6", "Room 7"]

tahoe_rooms =
  Enum.map(room_names, fn name ->
    room_attrs =
      cond do
        name == "Room 5a" ->
          # Single bed room
          %{
            name: name,
            description: "Cozy single bed room with 1 single bed. Perfect for solo travelers.",
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
          # Single bed room
          %{
            name: name,
            description: "Cozy single bed room with 1 single bed. Perfect for solo travelers.",
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
          # Family room
          %{
            name: name,
            description: "Spacious family room with 1 queen bed and 3 single beds. Accommodates up to 5 guests. Minimum 2 guests required.",
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
          # Standard room - 2 guests
          %{
            name: name,
            description: "Comfortable room with 2 single beds. Perfect for two guests.",
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
          # Standard room - 2 guests
          %{
            name: name,
            description: "Comfortable room with 1 queen bed. Ideal for couples or two guests.",
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
          # Standard room - 2 guests
          %{
            name: name,
            description: "Comfortable room with 1 queen bed. Ideal for couples or two guests.",
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
          # Standard room - 3 guests
          %{
            name: name,
            description: "Spacious room with 1 queen bed and 1 single bed. Accommodates up to 3 guests.",
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
          # Standard room - 2 guests
          %{
            name: name,
            description: "Comfortable room with 1 queen bed. Ideal for couples or two guests.",
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
          # Default fallback
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

    case Repo.get_by(Room, name: name, property: :tahoe) do
      nil ->
        room =
          Room.changeset(%Room{}, room_attrs)
          |> Repo.insert!()

        IO.puts("  ✅ Created #{name}")
        room

      existing ->
        IO.puts("  ℹ️  #{name} already exists")
        existing
    end
  end)

# 7. Create pricing rules
IO.puts("💰 Creating pricing rules...")

# Helper to get or create pricing rule
get_or_create_pricing_rule = fn attrs ->
  import Ecto.Query

  # Build query to find existing rule
  query = from pr in PricingRule, where: pr.booking_mode == ^attrs.booking_mode
  query = from pr in query, where: pr.price_unit == ^attrs.price_unit
  query = from pr in query, where: pr.property == ^attrs.property

  query =
    if Map.has_key?(attrs, :room_id) and not is_nil(attrs.room_id) do
      from pr in query, where: pr.room_id == ^attrs.room_id
    else
      from pr in query, where: is_nil(pr.room_id)
    end

  query =
    if Map.has_key?(attrs, :room_category_id) and not is_nil(attrs.room_category_id) do
      from pr in query, where: pr.room_category_id == ^attrs.room_category_id
    else
      from pr in query, where: is_nil(pr.room_category_id)
    end

  query =
    if Map.has_key?(attrs, :season_id) and not is_nil(attrs.season_id) do
      from pr in query, where: pr.season_id == ^attrs.season_id
    else
      from pr in query, where: is_nil(pr.season_id)
    end

  case Repo.one(query) do
    nil ->
      PricingRule.changeset(%PricingRule{}, attrs)
      |> Repo.insert!()

    existing ->
      # Update existing rule if children_amount is provided and not already set
      if Map.has_key?(attrs, :children_amount) && is_nil(existing.children_amount) do
        existing
        |> PricingRule.changeset(%{children_amount: attrs.children_amount})
        |> Repo.update!()
      else
        existing
      end
  end
end

# Clear Lake: Day bookings - $50 per person per night
get_or_create_pricing_rule.(%{
  amount: Money.new(50, :USD),
  booking_mode: :day,
  price_unit: :per_guest_per_day,
  property: :clear_lake,
  season_id: nil
})

IO.puts("  ✅ Created Clear Lake day pricing")

# Clear Lake: Buyout - $500 per night
get_or_create_pricing_rule.(%{
  amount: Money.new(500, :USD),
  booking_mode: :buyout,
  price_unit: :buyout_fixed,
  property: :clear_lake,
  season_id: nil
})

IO.puts("  ✅ Created Clear Lake buyout pricing")

# Tahoe: Summer buyout - $425 per night
get_or_create_pricing_rule.(%{
  amount: Money.new(425, :USD),
  booking_mode: :buyout,
  price_unit: :buyout_fixed,
  property: :tahoe,
  season_id: tahoe_summer.id
})

IO.puts("  ✅ Created Tahoe summer buyout pricing")

# Tahoe: Base room pricing for standard rooms - $45 per person per night
standard_rule = get_or_create_pricing_rule.(%{
  amount: Money.new(45, :USD),
  children_amount: Money.new(25, :USD),
  booking_mode: :room,
  price_unit: :per_person_per_night,
  property: :tahoe,
  room_category_id: standard_category.id,
  season_id: nil
})

IO.puts("  ✅ Created Tahoe standard room pricing")

# Tahoe: Single bed room pricing - $35 per person per night
single_rule = get_or_create_pricing_rule.(%{
  amount: Money.new(35, :USD),
  children_amount: Money.new(25, :USD),
  booking_mode: :room,
  price_unit: :per_person_per_night,
  property: :tahoe,
  room_category_id: single_category.id,
  season_id: nil
})

IO.puts("  ✅ Created Tahoe single room pricing")

# Tahoe: Family room pricing - same as standard ($45 per person per night)
family_rule = get_or_create_pricing_rule.(%{
  amount: Money.new(45, :USD),
  children_amount: Money.new(25, :USD),
  booking_mode: :room,
  price_unit: :per_person_per_night,
  property: :tahoe,
  room_category_id: family_category.id,
  season_id: nil
})

IO.puts("  ✅ Created Tahoe family room pricing")

# Create a property-level fallback rule for children pricing
get_or_create_pricing_rule.(%{
  amount: Money.new(45, :USD),
  children_amount: Money.new(25, :USD),
  booking_mode: :room,
  price_unit: :per_person_per_night,
  property: :tahoe,
  room_id: nil,
  room_category_id: nil,
  season_id: nil
})

IO.puts("  ✅ Created Tahoe property-level fallback pricing")

# 8. Create refund policies
IO.puts("📋 Creating refund policies...")

# Tahoe Full Cabin (Buyout) Policy
# Use direct database query to avoid cache initialization issues in seed scripts
tahoe_buyout_policy =
  case Bookings.get_active_refund_policy_db(:tahoe, :buyout) do
    nil ->
      policy =
        Bookings.create_refund_policy!(%{
          name: "Tahoe Full Cabin Cancellation Policy",
          description: "Cancellation policy for full cabin (buyout) bookings at Tahoe property",
          property: :tahoe,
          booking_mode: :buyout,
          is_active: true
        })

      IO.puts("  ✅ Created Tahoe buyout refund policy")
      policy

    existing_policy ->
      IO.puts("  ℹ️  Tahoe buyout refund policy already exists")
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

      IO.puts("    ✅ Created rule: <14 days = 0% refund")

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

      IO.puts("    ✅ Created rule: <21 days = 50% refund")

    _ ->
      :ok
  end
end

# Tahoe Rooms Policy
# Use direct database query to avoid cache initialization issues in seed scripts
tahoe_room_policy =
  case Bookings.get_active_refund_policy_db(:tahoe, :room) do
    nil ->
      policy =
        Bookings.create_refund_policy!(%{
          name: "Tahoe Rooms Cancellation Policy",
          description: "Cancellation policy for room bookings at Tahoe property",
          property: :tahoe,
          booking_mode: :room,
          is_active: true
        })

      IO.puts("  ✅ Created Tahoe room refund policy")
      policy

    existing_policy ->
      IO.puts("  ℹ️  Tahoe room refund policy already exists")
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

      IO.puts("    ✅ Created rule: <7 days = 0% refund")

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

      IO.puts("    ✅ Created rule: <14 days = 50% refund")

    _ ->
      :ok
  end
end

# Clear Lake Buyout Policy
# Use direct database query to avoid cache initialization issues in seed scripts
clear_lake_buyout_policy =
  case Bookings.get_active_refund_policy_db(:clear_lake, :buyout) do
    nil ->
      policy =
        Bookings.create_refund_policy!(%{
          name: "Clear Lake Full Cabin Cancellation Policy",
          description: "Cancellation policy for full cabin (buyout) bookings at Clear Lake property",
          property: :clear_lake,
          booking_mode: :buyout,
          is_active: true
        })

      IO.puts("  ✅ Created Clear Lake buyout refund policy")
      policy

    existing_policy ->
      IO.puts("  ℹ️  Clear Lake buyout refund policy already exists")
      existing_policy
  end

# Create rules for Clear Lake buyout policy
if clear_lake_buyout_policy do
  # Rule 1: Less than 14 days = 0% refund (100% forfeiture)
  case Bookings.list_refund_policy_rules(clear_lake_buyout_policy.id)
       |> Enum.find(fn r -> r.days_before_checkin == 14 end) do
    nil ->
      Bookings.create_refund_policy_rule!(%{
        refund_policy_id: clear_lake_buyout_policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("0"),
        description:
          "Reservations cancelled less than 14 days prior to date of arrival will result in forfeiture of 100% of the cost",
        priority: 0
      })

      IO.puts("    ✅ Created rule: <14 days = 0% refund")

    _ ->
      :ok
  end

  # Rule 2: Less than 21 days = 50% refund (50% forfeiture)
  case Bookings.list_refund_policy_rules(clear_lake_buyout_policy.id)
       |> Enum.find(fn r -> r.days_before_checkin == 21 end) do
    nil ->
      Bookings.create_refund_policy_rule!(%{
        refund_policy_id: clear_lake_buyout_policy.id,
        days_before_checkin: 21,
        refund_percentage: Decimal.new("50"),
        description:
          "Reservations cancelled less than 21 days prior to date of arrival are subject to forfeiture of 50% of the cost",
        priority: 0
      })

      IO.puts("    ✅ Created rule: <21 days = 50% refund")

    _ ->
      :ok
  end
end

# Clear Lake Day Policy
# Use direct database query to avoid cache initialization issues in seed scripts
clear_lake_day_policy =
  case Bookings.get_active_refund_policy_db(:clear_lake, :day) do
    nil ->
      policy =
        Bookings.create_refund_policy!(%{
          name: "Clear Lake Day Booking Cancellation Policy",
          description: "Cancellation policy for day bookings at Clear Lake property",
          property: :clear_lake,
          booking_mode: :day,
          is_active: true
        })

      IO.puts("  ✅ Created Clear Lake day refund policy")
      policy

    existing_policy ->
      IO.puts("  ℹ️  Clear Lake day refund policy already exists")
      existing_policy
  end

# Create rules for Clear Lake day policy
if clear_lake_day_policy do
  # Rule 1: Less than 7 days = 0% refund (100% forfeiture)
  case Bookings.list_refund_policy_rules(clear_lake_day_policy.id)
       |> Enum.find(fn r -> r.days_before_checkin == 7 end) do
    nil ->
      Bookings.create_refund_policy_rule!(%{
        refund_policy_id: clear_lake_day_policy.id,
        days_before_checkin: 7,
        refund_percentage: Decimal.new("0"),
        description:
          "Reservations cancelled less than 7 days prior to date of arrival will result in forfeiture of 100% of the cost",
        priority: 0
      })

      IO.puts("    ✅ Created rule: <7 days = 0% refund")

    _ ->
      :ok
  end

  # Rule 2: Less than 14 days = 50% refund (50% forfeiture)
  case Bookings.list_refund_policy_rules(clear_lake_day_policy.id)
       |> Enum.find(fn r -> r.days_before_checkin == 14 end) do
    nil ->
      Bookings.create_refund_policy_rule!(%{
        refund_policy_id: clear_lake_day_policy.id,
        days_before_checkin: 14,
        refund_percentage: Decimal.new("50"),
        description:
          "Reservations cancelled less than 14 days prior to date of arrival are subject to forfeiture of 50% of the cost",
        priority: 0
      })

      IO.puts("    ✅ Created rule: <14 days = 50% refund")

    _ ->
      :ok
  end
end

IO.puts("\n✅ Production seed completed successfully!")
IO.puts("   - SiteSettings: Instagram and Facebook")
IO.puts("   - Admin user: admin@ysc.org")
IO.puts("   - Tahoe seasons: Winter and Summer")
IO.puts("   - Clear Lake seasons: Winter and Summer")
IO.puts("   - Room categories: single, standard, family")
IO.puts("   - Tahoe rooms: 8 rooms")
IO.puts("   - Pricing rules: Tahoe and Clear Lake")
IO.puts("   - Refund policies: Tahoe (buyout, room) and Clear Lake (buyout, day)")
IO.puts("\n⚠️  Note: Make sure to set ADMIN_PASSWORD environment variable in production!")
