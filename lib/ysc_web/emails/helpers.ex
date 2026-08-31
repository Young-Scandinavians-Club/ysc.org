defmodule YscWeb.Emails.Helpers do
  @moduledoc """
  Shared helpers for MJML email modules: public URLs, salutation names,
  event cover images / association preloading, and display formatting
  for money and dates.
  """

  alias HtmlSanitizeEx
  alias Ysc.Events.Event
  alias Ysc.Media.Image
  alias Ysc.Repo

  @member_default "Valued Member"
  @attendee_default "there"
  @email_timezone "America/Los_Angeles"
  @money_display_opts [separator: ".", delimiter: ",", fractional_digits: 2]

  @doc """
  Returns the public site origin (`YscWeb.Endpoint.url/0`), with no trailing slash.
  """
  def origin, do: YscWeb.Endpoint.url()

  @doc """
  Builds an absolute URL for a path that starts with `/`.
  """
  def absolute_url("/" <> _rest = path), do: origin() <> path

  @doc """
  Returns a first name for member-facing greetings.

  Uses `#{@member_default}` when the name is nil, empty, or only whitespace.
  Accepts a raw name (`nil` or `String.t()`) or any map/struct with a `:first_name` field.
  """
  def member_greeting_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> @member_default
      trimmed -> trimmed
    end
  end

  def member_greeting_name(nil), do: @member_default

  def member_greeting_name(%{} = entity) do
    entity
    |> Map.get(:first_name)
    |> member_greeting_name()
  end

  def member_greeting_name(_), do: @member_default

  @doc """
  Returns a first name for attendee-facing greetings (ticket holders).

  Accepts atom- or string-keyed maps. Uses `#{@attendee_default}` when the name
  is missing. Does not trim — empty strings are kept, matching historical
  `prepare_email_data` behavior.
  """
  def attendee_greeting_name(recipient, default \\ @attendee_default)

  def attendee_greeting_name(recipient, default) when is_map(recipient) do
    Map.get(recipient, :first_name) || Map.get(recipient, "first_name") ||
      default
  end

  def attendee_greeting_name(_, default), do: default

  @doc """
  Absolute URL for the member membership management page.
  """
  def membership_url, do: absolute_url("/users/membership")

  @doc """
  Absolute URL for the public events listing.
  """
  def upcoming_events_url, do: absolute_url("/events")

  @doc """
  Absolute URL for a public event page.
  """
  def event_url(event_id), do: absolute_url("/events/#{event_id}")

  @doc """
  Absolute URL for member notification settings.
  """
  def notification_settings_url, do: absolute_url("/users/notifications")

  @doc """
  Absolute URL for Tahoe cabin booking.
  """
  def tahoe_booking_url, do: absolute_url("/bookings/tahoe")

  @doc """
  Absolute URL for the member page where a card or bank account can be saved.
  """
  def payment_methods_url, do: absolute_url("/users/membership/payment-method")

  @doc """
  Absolute URL for the member security settings page.
  """
  def security_settings_url, do: absolute_url("/users/settings/security")

  @doc """
  Absolute URL for the admin dashboard.
  """
  def admin_dashboard_url, do: absolute_url("/admin")

  @doc """
  Formats sign-in method from an auth event for email copy.
  """
  def sign_in_method_label(%{metadata: metadata}) when is_map(metadata) do
    method = Map.get(metadata, "auth_method") || Map.get(metadata, :auth_method)

    case method do
      "email_password" -> "Password"
      "passkey" -> "Passkey"
      "google" -> "Google"
      "facebook" -> "Facebook"
      "oauth" -> "Google or Facebook"
      other when is_binary(other) and other != "" -> String.capitalize(other)
      _ -> "Sign-in"
    end
  end

  def sign_in_method_label(_), do: "Sign-in"

  @doc """
  Formats device/browser details from an auth event for email copy.
  """
  def sign_in_device_description(%{browser: browser, operating_system: os}) do
    browser_label = browser || "Unknown browser"
    os_label = os || "Unknown OS"
    "#{browser_label} on #{os_label}"
  end

  @doc """
  Formats location from an auth event for email copy.
  """
  def sign_in_location(event) do
    case format_sign_in_geo_location(event) do
      geo when is_binary(geo) and geo != "" ->
        geo

      _ ->
        case Ysc.IpAddress.mask(event.ip_address) do
          masked when is_binary(masked) -> masked
          _ -> "Unknown location"
        end
    end
  end

  defp format_sign_in_geo_location(event) do
    country_label = sign_in_country_label(event.country)

    [event.city, event.region, country_label]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> case do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  defp sign_in_country_label(nil), do: nil
  defp sign_in_country_label(""), do: nil

  defp sign_in_country_label(country_code) when is_binary(country_code) do
    country_code = country_code |> String.trim() |> String.upcase()

    case Cldr.Territory.display_name(country_code, backend: Ysc.Cldr) do
      {:ok, name} -> name
      _ -> country_code
    end
  end

  @doc """
  Absolute URL for the public news listing.
  """
  def news_url, do: absolute_url("/news")

  @doc """
  Absolute URL for the site home page.
  """
  def home_url, do: absolute_url("/")

  @doc """
  Shared assign map for membership payment reminder emails (7-day and 30-day).
  """
  def membership_payment_reminder_data(user) do
    if is_nil(user) do
      raise ArgumentError, "User cannot be nil"
    end

    %{
      first_name: member_greeting_name(user),
      pay_membership_url: membership_url(),
      upcoming_events_url: upcoming_events_url()
    }
  end

  @doc """
  Formats a date for email copy (`"January 15, 2026"`).

  ISO8601 date strings are parsed when possible. Returns `default` when the
  value is nil, not a date/datetime, or not a parseable date string.
  """
  def format_date(value, default \\ "N/A")

  def format_date(nil, default), do: default

  def format_date(%Date{} = date, _default),
    do: Calendar.strftime(date, "%B %d, %Y")

  def format_date(%DateTime{} = datetime, default),
    do: format_date(DateTime.to_date(datetime), default)

  def format_date(date_string, default) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> format_date(date, default)
      {:error, _} -> default
    end
  end

  def format_date(_, default), do: default

  @doc """
  Formats a datetime in Pacific time for email copy.

  Returns `default` when the value is nil or not a datetime.
  """
  def format_datetime(value, default \\ "N/A")

  def format_datetime(nil, default), do: default

  def format_datetime(%DateTime{} = datetime, _default) do
    datetime
    |> DateTime.shift_zone!(@email_timezone)
    |> Calendar.strftime("%B %d, %Y at %I:%M %p %Z")
  end

  def format_datetime(_, default), do: default

  @doc """
  Formats an event's start date and time for email copy.

  Event `start_date` and `start_time` are stored as Pacific-local wall-clock
  values, not UTC. Do not apply timezone conversion.

  Returns `default` when `start_date` is nil.
  """
  def format_event_start_datetime(start_date, start_time, default \\ nil)

  def format_event_start_datetime(nil, _, default), do: default

  def format_event_start_datetime(date, nil, _default) do
    date
    |> event_date()
    |> Calendar.strftime("%B %d, %Y")
  end

  def format_event_start_datetime(date, %Time{} = time, _default) do
    date_only = event_date(date)
    date_str = Calendar.strftime(date_only, "%B %d, %Y")
    time_str = Calendar.strftime(time, "%-I:%M %p")
    tz_abbr = pacific_tz_abbreviation(date_only)
    "#{date_str} at #{time_str} #{tz_abbr}"
  end

  @doc """
  Display URL for an event's cover image, or `nil`.

  Returns `nil` when `cover_image` is not loaded or is nil. Call
  `preload_event_associations/2` first when the association may be unloaded.
  """
  def event_cover_image_url(%{cover_image: cover_image} = event) do
    if Ecto.assoc_loaded?(event.cover_image) do
      Image.display_path(cover_image)
    else
      nil
    end
  end

  @doc """
  Reloads the event with `associations` when any of them are not loaded.

  Defaults to `:organizer` and `:cover_image`. Raises if the event row no
  longer exists.
  """
  def preload_event_associations(
        event,
        associations \\ [:organizer, :cover_image]
      )

  def preload_event_associations(%Event{} = event, associations)
      when is_list(associations) do
    if Enum.all?(associations, &Ecto.assoc_loaded?(Map.fetch!(event, &1))) do
      event
    else
      case Repo.get(Event, event.id) |> Repo.preload(associations) do
        nil -> raise ArgumentError, "Event not found: #{event.id}"
        loaded -> loaded
      end
    end
  end

  @doc """
  Strips HTML tags and decodes entities for plain-text email copy.

  Returns `nil` for nil or empty input.
  """
  def plain_text_from_html(nil), do: nil
  def plain_text_from_html(""), do: nil

  def plain_text_from_html(html) when is_binary(html) do
    case YscWeb.PlainText.from_html(html) do
      "" -> nil
      text -> String.trim(text)
    end
  end

  @doc """
  Formats money for transactional emails (bookings, tickets, expenses).

  Uses comma thousands separators and two decimal places. Returns `default`
  for nil and non-money values.
  """
  def format_money(value, default \\ "$0.00")

  def format_money(nil, default), do: default

  def format_money(%Money{} = money, _default),
    do: Money.to_string!(money, @money_display_opts)

  def format_money(_, default), do: default

  @doc """
  Formats money for membership emails using Money's default string style.

  Returns `default` for nil and non-money values.
  """
  def format_membership_money(value, default \\ "N/A")

  def format_membership_money(nil, default), do: default

  def format_membership_money(%Money{} = money, _default),
    do: Money.to_string!(money)

  def format_membership_money(_, default), do: default

  defp event_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp event_date(%Date{} = date), do: date

  defp pacific_tz_abbreviation(%Date{} = date) do
    date
    |> NaiveDateTime.new!(~T[12:00:00])
    |> DateTime.from_naive!(@email_timezone)
    |> Calendar.strftime("%Z")
  end
end
