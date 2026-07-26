defmodule YscWeb.Emails.OutageNotification do
  @moduledoc """
  Email template for property outage notifications.

  Sends an email to users with active bookings when an outage is detected.
  """
  use MjmlEEx,
    mjml_template: "templates/outage_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Accounts.User
  alias Ysc.Bookings.PropertyDisplay
  alias Ysc.Repo
  import Ecto.Query
  import YscWeb.Emails.Helpers, only: [format_date: 2]

  def get_template_name() do
    "outage_notification"
  end

  def get_subject() do
    "Property Outage Alert - Young Scandinavians Club"
  end

  def property_name(property), do: PropertyDisplay.outage_name(property)

  def incident_type_name(incident_type) when is_atom(incident_type) do
    case incident_type do
      :power_outage -> "Power Outage"
      :water_outage -> "Water Outage"
      :internet_outage -> "Internet Outage"
      _ -> "Outage"
    end
  end

  def incident_type_name(incident_type) when is_binary(incident_type) do
    incident_type
    |> String.to_existing_atom()
    |> incident_type_name()
  rescue
    ArgumentError ->
      case incident_type do
        "power_outage" -> "Power Outage"
        "water_outage" -> "Water Outage"
        "internet_outage" -> "Internet Outage"
        _ -> "Outage"
      end
  end

  def incident_type_name(_), do: "Outage"

  def provider_outage_map_url(company_name) do
    case company_name do
      "Optimum" ->
        "https://www.optimum.com/outage-map"

      "Liberty Utilities" ->
        "https://myaccount.libertyenergyandwater.com/portal/#/PreOutages"

      "PG&E" ->
        "https://pgealerts.alerts.pge.com/outage-center/"

      "SCG" ->
        "https://www.swgas.com/outages"

      _ ->
        nil
    end
  end

  def format_date(value) when is_binary(value) or is_struct(value, Date),
    do: format_date(value, "Unknown date")

  def format_date(_), do: "Unknown date"

  @doc """
  Builds email template variables for an outage notification.

  Expects `booking` with a preloaded `:user` association.
  """
  def build_notification_variables(booking, outage) do
    first_name = booking.user.first_name || booking.user.email
    cabin_master = get_cabin_master(outage.property)

    cabin_master_name =
      if cabin_master do
        "#{cabin_master.first_name || ""} #{cabin_master.last_name || ""}"
        |> String.trim()
      end

    cabin_master_phone =
      if cabin_master do
        Ysc.Extensions.PhoneNumber.format_for_display(cabin_master.phone_number) ||
          cabin_master.phone_number
      end

    cabin_master_email = get_cabin_master_email(outage.property)

    %{
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
  end

  @doc """
  Plain-text body for outage notification emails.
  """
  def text_body(%{
        first_name: first_name,
        property: property,
        incident_type: incident_type,
        company_name: company_name,
        incident_date: incident_date,
        description: description,
        checkin_date: checkin_date,
        checkout_date: checkout_date,
        cabin_master_name: cabin_master_name,
        cabin_master_phone: cabin_master_phone,
        cabin_master_email: cabin_master_email
      }) do
    """
    Hej #{first_name},

    We wanted to let you know that a #{incident_type_name(incident_type)} has been reported at the #{property_name(property)}.

    Outage Details:
    - Type: #{incident_type_name(incident_type)}
    - Provider: #{company_name}
    - Date: #{format_date(incident_date)}
    #{if description, do: "- Description: #{description}", else: ""}

    Your Booking:
    - Check-in: #{format_date(checkin_date)}
    - Check-out: #{format_date(checkout_date)}

    #{cabin_master_contact_section(cabin_master_name, cabin_master_phone, cabin_master_email)}

    We recommend checking the provider's outage map for the latest status and estimated restoration time.

    #{outage_map_section(company_name)}

    Please note that outages can be unpredictable and restoration times may vary. We recommend checking the provider's website for the most up-to-date information.

    If you have any questions or concerns, please don't hesitate to reach out to us.

    Young Scandinavians Club
    """
  end

  defp cabin_master_contact_section(
         cabin_master_name,
         cabin_master_phone,
         cabin_master_email
       ) do
    if cabin_master_name || cabin_master_email do
      """
      If you have any issues or need help, please reach out to the cabin master:

      #{if cabin_master_name, do: "- Cabin Master: #{cabin_master_name}\n", else: ""}#{if cabin_master_phone, do: "- Phone: #{cabin_master_phone}\n", else: ""}#{if cabin_master_email, do: "- Email: #{cabin_master_email}\n", else: ""}
      """
    else
      ""
    end
  end

  defp outage_map_section(company_name) do
    case provider_outage_map_url(company_name) do
      nil -> ""
      url -> "View Outage Map: #{url}"
    end
  end

  @doc """
  Gets the cabin master for a given property.
  Returns the most recently updated user with the cabin master position.
  """
  def get_cabin_master(property) when is_atom(property) do
    board_position =
      case property do
        :tahoe -> :tahoe_cabin_master
        :clear_lake -> :clear_lake_cabin_master
        _ -> nil
      end

    if board_position do
      from(u in User,
        where: u.board_position == ^board_position,
        order_by: [desc: u.updated_at],
        limit: 1
      )
      |> Repo.one()
    else
      nil
    end
  end

  def get_cabin_master(property) when is_binary(property) do
    property
    |> String.to_existing_atom()
    |> get_cabin_master()
  rescue
    ArgumentError ->
      case property do
        "tahoe" -> get_cabin_master(:tahoe)
        "clear_lake" -> get_cabin_master(:clear_lake)
        _ -> nil
      end
  end

  def get_cabin_master(_), do: nil

  @doc """
  Gets the cabin master email for a given property.
  Returns the specific email address for the property.
  """
  def get_cabin_master_email(property) when is_atom(property) do
    case property do
      :tahoe -> Ysc.EmailConfig.tahoe_email()
      :clear_lake -> Ysc.EmailConfig.clear_lake_email()
      _ -> nil
    end
  end

  def get_cabin_master_email(property) when is_binary(property) do
    property
    |> String.to_existing_atom()
    |> get_cabin_master_email()
  rescue
    ArgumentError ->
      case property do
        "tahoe" -> Ysc.EmailConfig.tahoe_email()
        "clear_lake" -> Ysc.EmailConfig.clear_lake_email()
        _ -> nil
      end
  end

  def get_cabin_master_email(_), do: nil
end
