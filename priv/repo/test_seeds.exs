alias Ysc.Repo
alias Ysc.Bookings.Season
alias Ysc.Settings

Settings.seed_default_social_settings()

# Canonical seasons for the shared test DB. Committed rows survive SQL sandbox
# rollback, so polluted Winter (e.g. Aug–Apr from ad-hoc fixtures) makes buyout
# and uniqueness tests flake. Upsert by name+property on every mix test bootstrap.
base_year = 2024
winter_start = Date.new!(base_year, 11, 1)
winter_end = Date.new!(base_year + 1, 4, 30)
summer_start = Date.new!(base_year, 5, 1)
summer_end = Date.new!(base_year, 10, 31)

canonical_seasons = [
  %{
    name: "Winter",
    description: "Winter season for Tahoe cabin (Nov 1 - Apr 30, recurring annually)",
    property: :tahoe,
    start_date: winter_start,
    end_date: winter_end,
    is_default: false,
    advance_booking_days: 45,
    max_nights: 4
  },
  %{
    name: "Summer",
    description: "Summer season for Tahoe cabin (May 1 - Oct 31, recurring annually)",
    property: :tahoe,
    start_date: summer_start,
    end_date: summer_end,
    is_default: true,
    advance_booking_days: nil,
    max_nights: 4
  },
  %{
    name: "Winter",
    description: "Winter season for Clear Lake cabin (Nov 1 - Apr 30, recurring annually)",
    property: :clear_lake,
    start_date: winter_start,
    end_date: winter_end,
    is_default: false,
    advance_booking_days: nil,
    max_nights: 30
  },
  %{
    name: "Summer",
    description: "Summer season for Clear Lake cabin (May 1 - Oct 31, recurring annually)",
    property: :clear_lake,
    start_date: summer_start,
    end_date: summer_end,
    is_default: true,
    advance_booking_days: nil,
    max_nights: 30
  }
]

Enum.each(canonical_seasons, fn attrs ->
  case Repo.get_by(Season, name: attrs.name, property: attrs.property) do
    nil ->
      %Season{}
      |> Season.changeset(attrs)
      |> Repo.insert!()

    existing ->
      existing
      |> Season.changeset(attrs)
      |> Repo.update!()
  end
end)
