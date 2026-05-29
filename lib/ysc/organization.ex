defmodule Ysc.Organization do
  @moduledoc """
  Young Scandinavians Club organization details shared across the app.
  """

  @name "Young Scandinavians Club"
  @street_line_1 "28 Geary St"
  @street_line_2 "Ste 650 #304"
  @city_state_zip "San Francisco, CA 94108"

  @doc "Returns the organization's legal/display name."
  def name, do: @name

  @doc "Returns mailing address lines including the organization name."
  def mailing_address_lines do
    [@name, @street_line_1, @street_line_2, @city_state_zip]
  end

  @doc "Returns mailing address lines without the organization name."
  def mailing_address_street_lines do
    [@street_line_1, @street_line_2, @city_state_zip]
  end

  @doc "Returns the mailing address formatted for plain-text email bodies."
  def mailing_address_plain_text do
    mailing_address_lines() |> Enum.join("\n")
  end

  @doc "Returns the mailing address as a single line (street and city)."
  def mailing_address_single_line do
    "#{@street_line_1}, #{@street_line_2}, #{@city_state_zip}"
  end
end
