defmodule YscWeb.Emails.Helpers do
  @moduledoc """
  Shared helpers for MJML email modules: public URLs and salutation names.
  """

  @member_default "Valued Member"

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
end
