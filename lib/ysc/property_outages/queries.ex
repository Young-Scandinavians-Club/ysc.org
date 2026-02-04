defmodule Ysc.PropertyOutages.Queries do
  @moduledoc """
  Query helper functions for OutageTracker.

  Provides convenient functions for querying property outages from the database.
  """

  import Ecto.Query
  alias Ysc.PropertyOutages.OutageTracker
  alias Ysc.Repo

  @doc """
  Returns all outages.
  Note: Consider using `recent/1` with a limit for better performance.
  """
  def all do
    from(o in OutageTracker, order_by: [desc: o.inserted_at], limit: 1000)
    |> Repo.all()
  end

  @doc """
  Returns outages for a specific property.
  Limited to 1000 most recent to prevent unbounded queries.
  """
  def by_property(property) do
    from(o in OutageTracker,
      where: o.property == ^property,
      order_by: [desc: o.inserted_at],
      limit: 1000
    )
    |> Repo.all()
  end

  @doc """
  Returns outages of a specific type.
  Limited to 1000 most recent to prevent unbounded queries.
  """
  def by_incident_type(incident_type) do
    from(o in OutageTracker,
      where: o.incident_type == ^incident_type,
      order_by: [desc: o.inserted_at],
      limit: 1000
    )
    |> Repo.all()
  end

  @doc """
  Returns outages for a specific property and incident type.
  Limited to 1000 most recent to prevent unbounded queries.
  """
  def by_property_and_type(property, incident_type) do
    from(o in OutageTracker,
      where: o.property == ^property and o.incident_type == ^incident_type,
      order_by: [desc: o.inserted_at],
      limit: 1000
    )
    |> Repo.all()
  end

  @doc """
  Returns outages for a specific company.
  Limited to 1000 most recent to prevent unbounded queries.
  """
  def by_company(company_name) do
    from(o in OutageTracker,
      where: o.company_name == ^company_name,
      order_by: [desc: o.inserted_at],
      limit: 1000
    )
    |> Repo.all()
  end

  @doc """
  Returns the most recent outages, limited to the specified count.
  """
  def recent(limit \\ 10) do
    from(o in OutageTracker,
      order_by: [desc: o.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Returns outages on or after the given date.
  Limited to 1000 most recent to prevent unbounded queries.
  """
  def since_date(date) do
    from(o in OutageTracker,
      where: o.incident_date >= ^date,
      order_by: [desc: o.incident_date],
      limit: 1000
    )
    |> Repo.all()
  end

  @doc """
  Returns outages between two dates (inclusive).
  Limited to 1000 most recent to prevent unbounded queries.
  """
  def between_dates(start_date, end_date) do
    from(o in OutageTracker,
      where: o.incident_date >= ^start_date and o.incident_date <= ^end_date,
      order_by: [desc: o.incident_date],
      limit: 1000
    )
    |> Repo.all()
  end

  @doc """
  Returns outages created on or after the given datetime.
  Limited to 1000 most recent to prevent unbounded queries.
  """
  def created_since(datetime) do
    from(o in OutageTracker,
      where: o.inserted_at >= ^datetime,
      order_by: [desc: o.inserted_at],
      limit: 1000
    )
    |> Repo.all()
  end

  @doc """
  Returns the most recent outage for a specific property.
  """
  def latest_for_property(property) do
    from(o in OutageTracker,
      where: o.property == ^property,
      order_by: [desc: o.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns the most recent outage for a specific property and incident type.
  """
  def latest_for_property_and_type(property, incident_type) do
    from(o in OutageTracker,
      where: o.property == ^property and o.incident_type == ^incident_type,
      order_by: [desc: o.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Checks if there are any active outages for a property.

  An outage is considered "active" if it was created within the last 7 days.
  """
  def has_active_outage?(property, days \\ 7) do
    cutoff_date = Date.add(Date.utc_today(), -days)
    cutoff_datetime = NaiveDateTime.new!(cutoff_date, ~T[00:00:00])

    from(o in OutageTracker,
      where: o.property == ^property and o.inserted_at >= ^cutoff_datetime,
      select: count(o.id),
      limit: 1
    )
    |> Repo.one() > 0
  end

  @doc """
  Checks if there are any active outages for a property with a specific incident type.
  """
  def has_active_outage_by_type?(property, incident_type, days \\ 7) do
    cutoff_date = Date.add(Date.utc_today(), -days)
    cutoff_datetime = NaiveDateTime.new!(cutoff_date, ~T[00:00:00])

    from(o in OutageTracker,
      where:
        o.property == ^property and o.incident_type == ^incident_type and
          o.inserted_at >= ^cutoff_datetime,
      select: count(o.id),
      limit: 1
    )
    |> Repo.one() > 0
  end

  @doc """
  Returns all active outages for a property (within the last N days).
  Limited to 1000 most recent to prevent unbounded queries.
  """
  def active_outages_for_property(property, days \\ 7) do
    cutoff_date = Date.add(Date.utc_today(), -days)
    cutoff_datetime = NaiveDateTime.new!(cutoff_date, ~T[00:00:00])

    from(o in OutageTracker,
      where: o.property == ^property and o.inserted_at >= ^cutoff_datetime,
      order_by: [desc: o.inserted_at],
      limit: 1000
    )
    |> Repo.all()
  end

  @doc """
  Returns active outages for a property filtered by incident type.
  Limited to 1000 most recent to prevent unbounded queries.
  """
  def active_outages_for_property_and_type(property, incident_type, days \\ 7) do
    cutoff_date = Date.add(Date.utc_today(), -days)
    cutoff_datetime = NaiveDateTime.new!(cutoff_date, ~T[00:00:00])

    from(o in OutageTracker,
      where:
        o.property == ^property and o.incident_type == ^incident_type and
          o.inserted_at >= ^cutoff_datetime,
      order_by: [desc: o.inserted_at],
      limit: 1000
    )
    |> Repo.all()
  end

  @doc """
  Returns outages grouped by property.
  """
  def grouped_by_property do
    from(o in OutageTracker,
      group_by: o.property,
      select: {o.property, count(o.id)},
      order_by: o.property
    )
    |> Repo.all()
  end

  @doc """
  Returns outages grouped by incident type.
  """
  def grouped_by_incident_type do
    from(o in OutageTracker,
      group_by: o.incident_type,
      select: {o.incident_type, count(o.id)},
      order_by: o.incident_type
    )
    |> Repo.all()
  end

  @doc """
  Returns outages grouped by company.
  """
  def grouped_by_company do
    from(o in OutageTracker,
      group_by: o.company_name,
      select: {o.company_name, count(o.id)},
      order_by: o.company_name
    )
    |> Repo.all()
  end

  @doc """
  Gets an outage by incident_id.
  """
  def get_by_incident_id(incident_id) do
    Repo.get_by(OutageTracker, incident_id: incident_id)
  end

  @doc """
  Gets an outage by ID.
  """
  def get(id) do
    Repo.get(OutageTracker, id)
  end

  @doc """
  Returns a query for outages that can be further customized.
  """
  def base_query do
    from(o in OutageTracker)
  end
end
