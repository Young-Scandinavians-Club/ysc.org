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
end
