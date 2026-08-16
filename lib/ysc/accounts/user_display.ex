defmodule Ysc.Accounts.UserDisplay do
  @moduledoc """
  Human-readable labels for user profile and signup application fields.

  Centralizes country code formatting and birth-date display used across admin
  user list and user detail views.
  """

  @nordic_country_options ["Sweden", "Norway", "Finland", "Denmark", "Iceland"]

  @country_labels %{
    "SE" => "Sweden",
    "NO" => "Norway",
    "FI" => "Finland",
    "DK" => "Denmark",
    "IS" => "Iceland",
    "US" => "United States"
  }

  @flag_country_codes MapSet.new(Map.keys(@country_labels))

  @doc """
  Returns select options for the most-connected Nordic country field.
  """
  def nordic_country_options, do: @nordic_country_options

  @doc """
  Returns a display label for a country code or name.

  Accepts ISO-style codes (`"SE"`, `"us"`) and returns the full country name.
  Unknown codes are returned unchanged. Nil returns an empty string.
  """
  def country_label(nil), do: ""

  def country_label(code) when is_binary(code) do
    Map.get(@country_labels, normalize_country_code(code), code)
  end

  @doc """
  Returns a flag-icons CSS class (e.g. `"fi-se"`) for supported country codes.

  Returns `nil` when the code is nil, blank, or not in the supported set.
  """
  def country_flag_class(nil), do: nil

  def country_flag_class(code) when is_binary(code) do
    normalized = normalize_country_code(code)

    if MapSet.member?(@flag_country_codes, normalized) do
      "fi-#{String.downcase(normalized)}"
    else
      nil
    end
  end

  @doc """
  Formats a birth date for admin profile display.

  Returns an empty string for nil. Non-date values are converted with `to_string/1`.
  """
  def birth_date_label(nil), do: ""

  def birth_date_label(%Date{} = date),
    do: Timex.format!(date, "%b %d, %Y", :strftime)

  def birth_date_label(other), do: to_string(other)

  @doc """
  Returns the date a user's membership application was submitted.

  Falls back to when the application was reviewed, then to the user's account
  creation date, so this always returns a `DateTime` — never `nil` — even for
  users with no completed application (e.g. staff-created accounts, family
  sub-accounts, or abandoned signups).
  """
  def application_submitted_at(%{
        registration_form: %{completed: %DateTime{} = c}
      }),
      do: c

  def application_submitted_at(%{
        registration_form: %{reviewed_at: %DateTime{} = r}
      }),
      do: r

  def application_submitted_at(%{inserted_at: inserted_at}), do: inserted_at

  @doc """
  Returns a title-cased full name from a user struct or map with `first_name` and `last_name`.

  When both names are blank, returns `opts[:fallback]` (default `nil`).

  ## Examples

      iex> UserDisplay.full_name(%{first_name: "jane", last_name: "doe"})
      "Jane Doe"

      iex> UserDisplay.full_name(%{first_name: "jane", last_name: nil})
      "Jane"

      iex> UserDisplay.full_name(%{first_name: nil, last_name: nil}, fallback: "Unknown")
      "Unknown"
  """
  def full_name(user_or_map, opts \\ []) when is_map(user_or_map) do
    first = title_case_name(Map.get(user_or_map, :first_name))
    last = title_case_name(Map.get(user_or_map, :last_name))
    fallback = Keyword.get(opts, :fallback)

    cond do
      first != "" and last != "" -> "#{first} #{last}"
      first != "" -> first
      last != "" -> last
      true -> fallback
    end
  end

  @doc """
  Returns a title-cased first name for greetings and short labels.
  """
  def first_name_label(nil), do: ""

  def first_name_label(%{first_name: name}), do: title_case_name(name)

  def first_name_label(name) when is_binary(name), do: title_case_name(name)

  defp title_case_name(nil), do: ""

  defp title_case_name(name) do
    name
    |> to_string()
    |> String.trim()
    |> case do
      "" -> ""
      trimmed -> Ysc.title_case(trimmed)
    end
  end

  defp normalize_country_code(code) do
    code |> String.trim() |> String.upcase() |> String.slice(0, 2)
  end
end
