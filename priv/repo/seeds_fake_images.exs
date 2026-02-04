# Script to generate fake images across multiple years for testing
# Run with: mix run priv/repo/seeds_fake_images.exs

alias Ysc.Repo
alias Ysc.Accounts.User
alias Ysc.Media.Image
import Ecto.Query

# Get or create admin user
admin_user =
  case Repo.get_by(User, email: "admin@ysc.org") do
    nil ->
      IO.puts("⚠️  Admin user not found. Please run seeds.exs first or create a user.")
      # Try to get any user
      case Repo.all(from u in User, limit: 1) do
        [user] -> user
        [] -> raise "No users found. Please create a user first."
      end

    user ->
      user
  end

IO.puts("📸 Creating fake images for years 2010-2025...")
IO.puts("   Using user: #{admin_user.email}")

# Generate images across years 2010-2025
years = 2010..2025
images_per_year = 5..15  # Random number of images per year

total_created =
  Enum.reduce(years, 0, fn year, acc ->
    num_images = Enum.random(images_per_year)

    created_count =
      Enum.reduce(1..num_images, 0, fn i, count ->
        # Random date within the year
        month = Enum.random(1..12)
        day = Enum.random(1..28)  # Use 28 to avoid month-end issues
        hour = Enum.random(0..23)
        minute = Enum.random(0..59)
        second = Enum.random(0..59)

        inserted_at =
          DateTime.new!(Date.new!(year, month, day), Time.new!(hour, minute, second, 0), "Etc/UTC")

        # Generate fake but realistic image paths
        image_id = Ecto.ULID.generate()
        raw_path = "uploads/images/#{year}/#{image_id}.jpg"

        # Random dimensions (common image sizes)
        widths = [800, 1024, 1280, 1920, 2560]
        heights = [600, 768, 720, 1080, 1440]
        width = Enum.random(widths)
        height = Enum.random(heights)

        # Random titles
        titles = [
          "Event Photo #{year}",
          "Club Gathering #{year}",
          "Summer Event #{year}",
          "Winter Celebration #{year}",
          "Annual Meeting #{year}",
          "Social Event #{year}",
          "Community Photo #{year}",
          "Group Photo #{year}",
          "Activity #{year}",
          "Memories #{year}",
          nil,  # Some images without titles
          nil
        ]

        attrs = %{
          title: Enum.random(titles),
          alt_text: "Image from #{year}",
          raw_image_path: raw_path,
          optimized_image_path: "uploads/images/#{year}/#{image_id}_optimized.jpg",
          thumbnail_path: "uploads/images/#{year}/#{image_id}_thumb.jpg",
          blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",  # Default blurhash
          width: width,
          height: height,
          processing_state: "completed",
          user_id: admin_user.id,
          upload_data: %{
            filename: "fake_image_#{year}_#{i}.jpg",
            content_type: "image/jpeg"
          }
        }

        changeset = Image.add_image_changeset(%Image{}, attrs)

        case Repo.insert(changeset) do
          {:ok, image} ->
            # Update timestamps directly in the database
            Repo.update_all(
              from(i in Image, where: i.id == ^image.id),
              set: [inserted_at: inserted_at, updated_at: inserted_at]
            )
            count + 1

          {:error, changeset} ->
            IO.puts("  ❌ Failed to create image for #{year}: #{inspect(changeset.errors)}")
            count
        end
      end)

    IO.puts("  ✅ Created #{created_count} images for #{year}")
    acc + created_count
  end)

IO.puts("\n🎉 Done! Created #{total_created} fake images across #{Enum.count(years)} years.")
IO.puts("   Years: #{Enum.join(Enum.to_list(years), ", ")}")
