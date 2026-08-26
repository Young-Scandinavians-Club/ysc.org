defmodule YscWeb.EventBadgeHelpersTest do
  use ExUnit.Case, async: true

  alias YscWeb.EventBadgeHelpers

  defp pacific_today do
    DateTime.now!("America/Los_Angeles")
    |> DateTime.to_date()
  end

  defp utc_midnight(date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  defp base_event(overrides) do
    today = pacific_today()

    Map.merge(
      %{
        id: Ecto.ULID.generate(),
        state: :published,
        start_date: utc_midnight(Date.add(today, 7)),
        published_at: DateTime.utc_now() |> DateTime.truncate(:second),
        tickets_tbd: false,
        selling_fast: false,
        ticket_tiers: []
      },
      overrides
    )
  end

  describe "exclusive_badge_kinds/2" do
    test "cancelled suppresses all other badges" do
      event =
        base_event(%{
          state: :cancelled,
          start_date: utc_midnight(pacific_today()),
          tickets_tbd: true
        })

      assert EventBadgeHelpers.exclusive_badge_kinds(event,
               sold_out: true,
               selling_fast: true
             ) == [:cancelled]
    end

    test "sold out suppresses marketing and proximity badges" do
      event =
        base_event(%{
          start_date: utc_midnight(pacific_today()),
          tickets_tbd: true
        })

      assert EventBadgeHelpers.exclusive_badge_kinds(event,
               sold_out: true,
               selling_fast: true
             ) == [:sold_out]
    end

    test "unpublished events return no badges" do
      event =
        base_event(%{
          published_at: nil,
          start_date: utc_midnight(pacific_today())
        })

      assert EventBadgeHelpers.exclusive_badge_kinds(event, selling_fast: true) ==
               []
    end

    test "card proximity includes today, tomorrow, and days left" do
      today = pacific_today()

      assert [:today] =
               base_event(%{
                 start_date: utc_midnight(today),
                 published_at: DateTime.add(DateTime.utc_now(), -72, :hour)
               })
               |> EventBadgeHelpers.exclusive_badge_kinds(proximity: :labels)

      tomorrow = Date.add(today, 1)

      assert [:tomorrow] =
               base_event(%{
                 start_date: utc_midnight(tomorrow),
                 published_at: DateTime.add(DateTime.utc_now(), -72, :hour)
               })
               |> EventBadgeHelpers.exclusive_badge_kinds(proximity: :labels)

      two_days = Date.add(today, 2)

      assert [{:days_left, 2}] =
               base_event(%{
                 start_date: utc_midnight(two_days),
                 published_at: DateTime.add(DateTime.utc_now(), -72, :hour)
               })
               |> EventBadgeHelpers.exclusive_badge_kinds(proximity: :labels)
    end

    test "compact proximity uses days left for 1-3 days out" do
      today = pacific_today()
      two_days = Date.add(today, 2)

      assert [{:days_left, 2}] =
               base_event(%{
                 start_date: utc_midnight(two_days),
                 published_at: DateTime.add(DateTime.utc_now(), -72, :hour)
               })
               |> EventBadgeHelpers.exclusive_badge_kinds(proximity: :days_only)
    end

    test "includes marketing badges when published" do
      event =
        base_event(%{
          tickets_tbd: true,
          published_at: DateTime.add(DateTime.utc_now(), -12, :hour),
          start_date: utc_midnight(Date.add(pacific_today(), 10))
        })

      kinds =
        EventBadgeHelpers.exclusive_badge_kinds(event,
          selling_fast: true,
          proximity: :labels
        )

      assert :save_the_date in kinds
      assert :just_added in kinds
      assert :going_fast in kinds
    end
  end

  describe "hero_badge_kinds/1" do
    test "stacks applicable hero badges in display order" do
      event =
        base_event(%{
          tickets_tbd: true,
          state: :cancelled,
          selling_fast: true
        })

      assert EventBadgeHelpers.hero_badge_kinds(event) == [
               :save_the_date,
               :going_fast,
               :cancelled
             ]
    end
  end

  describe "formatters" do
    test "to_card_badges/1 maps kinds to card badge maps" do
      assert [%{text: "Today", class: "bg-red-600 text-white animate-pulse"}] =
               EventBadgeHelpers.to_card_badges([:today])
    end

    test "to_core_badges/1 maps kinds to badge type tuples" do
      assert [{"sky", "2 days left"}] =
               EventBadgeHelpers.to_core_badges([{:days_left, 2}])

      assert [{"sky", "1 day left"}] =
               EventBadgeHelpers.to_core_badges([{:days_left, 1}])
    end

    test "to_hero_badges/1 maps kinds to hero badge maps" do
      assert [%{text: "Going Fast!", icon: "hero-fire"}] =
               EventBadgeHelpers.to_hero_badges([:going_fast])
    end
  end

  describe "days_until_event_start/1" do
    test "returns nil for past events" do
      past = Date.add(pacific_today(), -1)

      assert EventBadgeHelpers.days_until_event_start(
               base_event(%{start_date: utc_midnight(past)})
             ) == nil
    end

    test "uses Pacific calendar days" do
      today = pacific_today()

      assert EventBadgeHelpers.days_until_event_start(
               base_event(%{start_date: utc_midnight(Date.add(today, 3))})
             ) == 3
    end

    test "uses Pacific calendar days, not the browser timezone" do
      pacific_today = pacific_today()
      auckland_today = DateTime.now!("Pacific/Auckland") |> DateTime.to_date()

      days =
        EventBadgeHelpers.days_until_event_start(
          base_event(%{start_date: utc_midnight(auckland_today)})
        )

      expected = Date.diff(auckland_today, pacific_today)

      if expected >= 0 do
        assert days == expected
      else
        assert days == nil
      end
    end
  end
end
