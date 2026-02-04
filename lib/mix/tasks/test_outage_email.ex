defmodule Mix.Tasks.TestOutageEmail do
  @moduledoc """
  Mix task to send a test outage notification email.

  Usage:
    mix test_outage_email [email]
    mix test_outage_email user@example.com

  If no email is provided, it will use the first user found in the database.
  """

  use Mix.Task
  require Logger
  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.Accounts.User
  alias Ysc.Bookings.Booking
  alias YscWeb.Emails.{Notifier, OutageNotification}

  @shortdoc "Send a test outage notification email"

  def run(args) do
    Mix.Task.run("app.start")

    email = List.first(args)

    if email do
      send_test_email(email)
    else
      # Find first user with email
      case find_user_with_email() do
        {:ok, user} ->
          send_test_email(user.email)

        {:error, reason} ->
          IO.puts("Error: #{reason}")
          IO.puts("\nUsage: mix test_outage_email [email]")
      end
    end
  end

  defp find_user_with_email do
    case Repo.one(from u in User, where: not is_nil(u.email), limit: 1) do
      nil ->
        {:error, "No users found in database"}

      user ->
        {:ok, user}
    end
  end

  defp send_test_email(email) do
    IO.puts("Sending test outage notification email to: #{email}")

    # Find or create a test user
    user =
      case Repo.get_by(User, email: email) do
        nil ->
          IO.puts("User not found with email: #{email}")
          IO.puts("Creating a test user...")
          create_test_user(email)

        user ->
          user
      end

    if user do
      # Create a test booking for the user
      booking = create_test_booking(user)

      # Create a test outage
      outage = create_test_outage()

      # Send the email
      send_outage_notification_email(booking, outage)

      IO.puts("\n✅ Test email sent successfully!")
      IO.puts("Check your email inbox at: #{email}")

      IO.puts(
        "\nNote: If using local mailer, check /dev/mailbox in your browser"
      )
    else
      IO.puts("Failed to create or find user")
    end
  end

  defp create_test_user(email) do
    %User{}
    |> User.registration_changeset(
      %{
        email: email,
        first_name: "Test",
        last_name: "User",
        password: "password123456",
        state: :active
      },
      validate_email: false
    )
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        IO.puts("Created test user: #{user.email}")
        user

      {:error, changeset} ->
        IO.puts("Error creating user: #{inspect(changeset.errors)}")
        nil
    end
  end

  defp create_test_booking(user) do
    today = Date.utc_today()
    checkin_date = Date.add(today, -1)
    checkout_date = Date.add(today, 2)

    %Booking{}
    |> Booking.changeset(
      %{
        user_id: user.id,
        property: :tahoe,
        booking_mode: :room,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        guests_count: 2,
        children_count: 0
      },
      skip_validation: true
    )
    |> Repo.insert()
    |> case do
      {:ok, booking} ->
        booking

      {:error, _changeset} ->
        # Booking might already exist, try to find it
        Repo.one(
          from b in Booking,
            where: b.user_id == ^user.id,
            order_by: [desc: b.inserted_at],
            limit: 1
        )
    end
  end

  defp create_test_outage do
    %{
      incident_id: "test_outage_#{System.system_time(:second)}",
      incident_type: :power_outage,
      company_name: "Liberty Utilities",
      description: "Test outage notification - This is a test email",
      incident_date: Date.utc_today(),
      property: :tahoe
    }
  end

  defp send_outage_notification_email(booking, outage) when is_map(outage) do
    # Ensure user is preloaded
    booking = Repo.preload(booking, :user)

    if booking.user && booking.user.email do
      # Use booking ID and incident type as idempotency key to prevent duplicate emails
      idempotency_key =
        "test_outage_alert_#{booking.id}_#{outage.incident_type}"

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
          IO.puts("Email job scheduled successfully")
          IO.puts("Idempotency key: #{idempotency_key}")

        {:error, reason} ->
          IO.puts("Failed to schedule email: #{inspect(reason)}")
      end
    else
      IO.puts("Booking has no user or email")
    end
  end
end
