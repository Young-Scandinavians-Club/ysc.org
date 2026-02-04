defmodule Ysc.PropertyOutages.PropertyOutageIncidentType do
  @moduledoc """
  Property outage incident type enum.
  """
  use EctoEnum,
    type: :property_outage_incident_type,
    enums: [:power_outage, :water_outage, :internet_outage]
end
