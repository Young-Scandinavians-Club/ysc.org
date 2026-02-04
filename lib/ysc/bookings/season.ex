defmodule Ysc.Bookings.Season do
  @moduledoc """
  Season schema and changesets.

  Defines the Season database schema for booking seasons (e.g., peak season, off-season).
  Seasons define time periods during which different pricing rules may apply.

  ## Recurring Seasons

  Seasons automatically recur every year based on their month/day pattern. For example:
  - Winter season: Nov 1 to Apr 30 (spans two calendar years but recurs annually)
  - Summer season: May 1 to Oct 31 (recurring annually)

  Use `for_date/2` to find which season applies to any date, regardless of the year.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Ysc.Repo

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "seasons" do
    field :name, :string
    field :description, :string

    # Property this season applies to
    field :property, Ysc.Bookings.BookingProperty

    # Season date range
    field :start_date, :date
    field :end_date, :date

    # Whether this is the default season for the property
    field :is_default, :boolean, default: false

    # Number of days in advance bookings can be made for this season
    # nil or 0 means no limit, otherwise it's the number of days (e.g., 45)
    field :advance_booking_days, :integer, default: nil

    # Maximum number of nights allowed for bookings in this season
    # nil means use property default (4 for Tahoe, 30 for Clear Lake)
    field :max_nights, :integer, default: nil

    # Relationships
    has_many :pricing_rules, Ysc.Bookings.PricingRule, foreign_key: :season_id
    has_many :rooms, Ysc.Bookings.Room, foreign_key: :default_season_id

    timestamps()
  end

  @doc """
  Creates a changeset for the Season schema.
  """
  def changeset(season, attrs \\ %{}) do
    season
    |> cast(attrs, [
      :name,
      :description,
      :property,
      :start_date,
      :end_date,
      :is_default,
      :advance_booking_days,
      :max_nights
    ])
    |> validate_number(:advance_booking_days, greater_than_or_equal_to: 0)
    |> validate_number(:max_nights, greater_than: 0)
    |> validate_required([
      :name,
      :property,
      :start_date,
      :end_date
    ])
    |> validate_length(:name, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_date_range()
    |> validate_default_season_uniqueness()
  end

  # Validates date range - allows year-spanning ranges (e.g., Nov 1 to Apr 30)
  defp validate_date_range(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date do
      validate_date_range_with_dates(changeset, start_date, end_date)
    else
      changeset
    end
  end

  defp validate_date_range_with_dates(changeset, start_date, end_date) do
    # Check if it's a year-spanning range (e.g., winter: Nov 1 to Apr 30)
    start_month = start_date.month
    end_month = end_date.month

    if start_month > end_month do
      # Year-spanning range (e.g., Nov to Apr) - this is valid
      changeset
    else
      # Same-year range - end must be after start
      validate_same_year_date_range(changeset, start_date, end_date)
    end
  end

  defp validate_same_year_date_range(changeset, start_date, end_date) do
    if Date.compare(end_date, start_date) != :gt do
      add_error(changeset, :end_date, "must be after start date")
    else
      changeset
    end
  end

  # Validates that only one default season exists per property
  defp validate_default_season_uniqueness(changeset) do
    is_default = get_field(changeset, :is_default)
    property = get_field(changeset, :property)
    season_id = get_field(changeset, :id)

    if is_default && property do
      # Check if there's another default season for this property
      query =
        if season_id do
          from s in Ysc.Bookings.Season,
            where:
              s.property == ^property and s.is_default == true and
                s.id != ^season_id
        else
          from s in Ysc.Bookings.Season,
            where: s.property == ^property and s.is_default == true
        end

      case Ysc.Repo.one(query) do
        nil ->
          changeset

        _existing ->
          add_error(
            changeset,
            :is_default,
            "only one default season allowed per property"
          )
      end
    else
      changeset
    end
  end

  @doc """
  Finds the season that applies to a given date for a property.

  Seasons are recurring annually. For year-spanning seasons (e.g., Nov 1 - Apr 30),
  the function checks if the date falls within the month/day range, regardless of year.

  ## Parameters
  - `property`: The property to find seasons for (:tahoe or :clear_lake)
  - `date`: The date to check (Date struct)

  ## Returns
  - `%Season{}` if a matching season is found
  - `nil` if no season matches
  """
  def for_date(property, date) when is_atom(property) do
    alias Ysc.Bookings.SeasonCache
    SeasonCache.get(property, date)
  end

  # Internal function that actually queries the database (called by cache on miss)
  def for_date_db(property, date) when is_atom(property) do
    query =
      from s in __MODULE__,
        where: s.property == ^property

    seasons = Repo.all(query)

    find_season_for_date(seasons, date)
  end

  # Internal function that queries all seasons for a property (used by cache)
  def list_all_for_property_db(property) when is_atom(property) do
    from(s in __MODULE__,
      where: s.property == ^property,
      order_by: [asc: s.name]
    )
    |> Repo.all()
  end

  @doc """
  Finds the season that applies to a given date from a pre-loaded list of seasons.

  This is an optimized version that avoids querying the database when seasons
  are already loaded. Use this when you have a cached list of seasons.

  ## Parameters
  - `seasons`: A list of Season structs (already loaded from database)
  - `date`: The date to check (Date struct)

  ## Returns
  - `%Season{}` if a matching season is found
  - `nil` if no season matches
  """
  def find_season_for_date(seasons, date) when is_list(seasons) do
    Enum.find(seasons, fn season ->
      date_in_season?(date, season.start_date, season.end_date)
    end)
  end

  @doc """
  Finds the default season for a property.

  ## Parameters
  - `property`: The property to find the default season for

  ## Returns
  - `%Season{}` if found
  - `nil` if no default season exists
  """
  def default_for_property(property) when is_atom(property) do
    Repo.get_by(__MODULE__, property: property, is_default: true)
  end

  @doc """
  Gets the maximum number of nights allowed for a season or property.

  If the season has a max_nights value, it's used. Otherwise, property defaults apply:
  - Tahoe: 4 nights
  - Clear Lake: 30 nights

  ## Parameters
  - `season`: A Season struct or nil
  - `property`: The property (:tahoe or :clear_lake)

  ## Returns
  - Integer: Maximum number of nights allowed
  """
  def get_max_nights(nil, property) when property in [:tahoe, :clear_lake] do
    case property do
      :tahoe -> 4
      :clear_lake -> 30
    end
  end

  def get_max_nights(%__MODULE__{max_nights: nil} = season, _property) do
    case season.property do
      :tahoe -> 4
      :clear_lake -> 30
    end
  end

  def get_max_nights(%__MODULE__{max_nights: max_nights}, _property)
      when is_integer(max_nights) do
    max_nights
  end

  # Checks if a date falls within a recurring season pattern
  # Handles year-spanning ranges (e.g., Nov 1 to Apr 30)
  defp date_in_season?(date, start_date, end_date) do
    {date_month, date_day} = {date.month, date.day}
    {start_month, start_day} = {start_date.month, start_date.day}
    {end_month, end_day} = {end_date.month, end_date.day}

    # If season spans years (e.g., Nov to Apr)
    if start_month > end_month do
      # Date is in season if it's >= start (Nov 1) OR <= end (Apr 30)
      {date_month, date_day} >= {start_month, start_day} or
        {date_month, date_day} <= {end_month, end_day}
    else
      # Same-year range (e.g., May to Oct)
      {date_month, date_day} >= {start_month, start_day} and
        {date_month, date_day} <= {end_month, end_day}
    end
  end
end
