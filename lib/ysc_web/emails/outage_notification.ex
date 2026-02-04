defmodule YscWeb.Emails.OutageNotification do
  @moduledoc """
  Email template for property outage notifications.

  Sends an email to users with active bookings when an outage is detected.
  """
  use MjmlEEx,
    mjml_template: "templates/outage_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Accounts.User
  alias Ysc.Repo
  import Ecto.Query

  def get_template_name() do
    "outage_notification"
  end

  def get_subject() do
    "Property Outage Alert - Young Scandinavians Club"
  end

  def property_name(property) when is_atom(property) do
    case property do
      :tahoe -> "Tahoe Property"
      :clear_lake -> "Clear Lake Property"
      _ -> "Property"
    end
  end

  def property_name(property) when is_binary(property) do
    property
    |> String.to_existing_atom()
    |> property_name()
  rescue
    ArgumentError ->
      case property do
        "tahoe" -> "Tahoe Property"
        "clear_lake" -> "Clear Lake Property"
        _ -> "Property"
      end
  end

  def property_name(_), do: "Property"

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

  def format_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date_struct} ->
        Calendar.strftime(date_struct, "%B %d, %Y")

      {:error, _} ->
        date
    end
  end

  def format_date(%Date{} = date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  def format_date(_) do
    "Unknown date"
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
