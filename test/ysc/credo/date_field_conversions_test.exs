defmodule Ysc.Credo.DateFieldConversionsTest do
  use ExUnit.Case, async: true

  alias Ysc.Credo.DateFieldConversions

  setup_all do
    {:ok, _} = Application.ensure_all_started(:credo)
    :ok
  end

  defp issues_for(source) do
    source
    |> Credo.SourceFile.parse("lib/ysc_web/live/sample_live.ex")
    |> DateFieldConversions.run([])
  end

  test "flags shift_zone on @event.start_date" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def days_until(assigns) do
          @event.start_date
          |> DateTime.shift_zone!("America/Los_Angeles")
          |> DateTime.to_date()
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldConversions}] = issues
  end

  test "flags shift_zone on event.start_date" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def days_until(event) do
          event.start_date
          |> DateTime.shift_zone!("America/Los_Angeles")
          |> DateTime.to_date()
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldConversions}] = issues
    assert hd(issues).message =~ "shift_zone"
  end

  test "flags format_date_in_zone on event.start_date" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def label(event, timezone) do
          YscWeb.DateDisplay.format_date_in_zone(event.start_date, timezone)
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldConversions}] = issues
  end

  test "allows format_event_date_range on event" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def label(event) do
          YscWeb.DateDisplay.format_event_date_range(event)
        end
      end
      """)

    assert issues == []
  end

  test "flags format_event_date_range on a ticket tier" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def label(ticket_tier) do
          YscWeb.DateDisplay.format_event_date_range(ticket_tier)
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldConversions}] = issues
    assert hd(issues).message =~ "format_sale_window_range"
  end

  test "flags days_until_event/2" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def label(event, timezone) do
          YscWeb.DateDisplay.days_until_event(event, timezone)
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldConversions}] = issues
    assert hd(issues).message =~ "Pacific today"
  end

  test "allows shift_zone on a UTC instant (post.published_on)" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def label(post, timezone) do
          YscWeb.DateDisplay.format_date_in_zone(post.published_on, timezone)
        end
      end
      """)

    assert issues == []
  end

  test "flags browser-timezone shift_zone on ticket_tier.start_date" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def label(ticket_tier, timezone) do
          DateTime.shift_zone!(ticket_tier.start_date, timezone)
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldConversions}] = issues
    assert hd(issues).message =~ "Pacific"
  end

  test "flags @timezone shift_zone on ticket_tier.start_date" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def label(ticket_tier) do
          ticket_tier.start_date
          |> DateTime.shift_zone!(@timezone)
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldConversions}] = issues
    assert hd(issues).message =~ "browser timezone"
  end

  test "allows Pacific shift_zone on ticket_tier.start_date" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def label(ticket_tier) do
          DateTime.shift_zone!(ticket_tier.start_date, "America/Los_Angeles")
        end
      end
      """)

    assert issues == []
  end

  test "allows TimeZone.default/0 shift_zone on ticket_tier.start_date" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        alias YscWeb.TimeZone

        def label(ticket_tier) do
          DateTime.shift_zone!(ticket_tier.start_date, TimeZone.default())
        end
      end
      """)

    assert issues == []
  end

  test "flags @timezone shift_zone on a case-bound ticket_tier.start_date variable" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def days_until_sale_starts(ticket_tier, timezone) do
          case ticket_tier.start_date do
            nil ->
              nil

            start_date ->
              start_date
              |> YscWeb.TimeZone.shift(timezone)
              |> DateTime.to_date()
          end
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldConversions}] = issues
    assert hd(issues).message =~ "Pacific"
  end

  test "allows Pacific shift_zone on a case-bound ticket_tier.start_date variable" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def days_until_sale_starts(ticket_tier) do
          case ticket_tier.start_date do
            nil ->
              nil

            start_date ->
              start_date
              |> YscWeb.TimeZone.shift(YscWeb.TimeZone.default())
              |> DateTime.to_date()
          end
        end
      end
      """)

    assert issues == []
  end

  test "flags shift_zone on a case-bound event.start_date variable (never shift)" do
    issues =
      issues_for("""
      defmodule YscWeb.SampleLive do
        def label(event) do
          case event.start_date do
            nil ->
              nil

            start_date ->
              DateTime.shift_zone!(start_date, "America/Los_Angeles")
          end
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldConversions}] = issues
    assert hd(issues).message =~ "Do not shift_zone"
  end
end
