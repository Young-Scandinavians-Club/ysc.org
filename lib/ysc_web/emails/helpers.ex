defmodule YscWeb.Emails.Helpers do
  @moduledoc """
  Shared helpers for MJML email modules: public URLs, salutation names, and
  display formatting for money and dates.
  """

  @member_default "Valued Member"
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
  Absolute URL for the member membership management page.
  """
  def membership_url, do: absolute_url("/users/membership")

  @doc """
  Absolute URL for the public events listing.
  """
  def upcoming_events_url, do: absolute_url("/events")

  @doc """
  Absolute URL for the member payment methods page.
  """
  def payment_methods_url, do: absolute_url("/users/payment-methods")

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

  Returns `default` when the value is nil or not a date/datetime.
  """
  def format_date(value, default \\ "N/A")

  def format_date(nil, default), do: default

  def format_date(%Date{} = date, _default),
    do: Calendar.strftime(date, "%B %d, %Y")

  def format_date(%DateTime{} = datetime, default),
    do: format_date(DateTime.to_date(datetime), default)

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
end
