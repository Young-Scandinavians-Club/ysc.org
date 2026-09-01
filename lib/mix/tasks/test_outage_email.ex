defmodule Mix.Tasks.TestOutageEmail do
  @moduledoc """
  Mix task to send a test outage notification email.

  Usage:
    mix test_outage_email [email]
    mix test_outage_email user@example.com

  If no email is provided, it will use the first user found in the database.
  """

  use Mix.Task

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

  @dialyzer {:nowarn_function, send_outage_notification_email: 2}
  defp send_outage_notification_email(booking, outage) when is_map(outage) do
    # Ensure user is preloaded
    booking = Repo.preload(booking, :user)

    if booking.user && booking.user.email do
      # Use booking ID and incident type as idempotency key to prevent duplicate emails
      idempotency_key =
        "test_outage_alert_#{booking.id}_#{outage.incident_type}"

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
