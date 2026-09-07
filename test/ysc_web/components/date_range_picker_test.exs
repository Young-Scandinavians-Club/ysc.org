defmodule YscWeb.Components.DateRangePickerTest do
  use ExUnit.Case, async: true

  alias YscWeb.Components.DateRangePicker

  @today ~D[2026-08-08]

  defp field(value) do
    %{
      value: value,
      name: "event[start_date]",
      id: "event_start_date",
      errors: []
    }
  end

  defp end_field(value) do
    %{
      value: value,
      name: "event[end_date]",
      id: "event_end_date",
      errors: []
    }
  end

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        id: "event_date",
        label: "Event date",
        start_date_field: field(""),
        end_date_field: end_field(""),
        required: false,
        is_range?: true,
        min: @today,
        min_nights: 0,
        today: @today,
        form: nil
      },
      overrides
    )
  end

  defp new_socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
  end

  defp init_socket(assigns) do
    {:ok, socket} = DateRangePicker.mount(new_socket())
    {:ok, socket} = DateRangePicker.update(assigns, socket)
    socket
  end

  defp iso_date(date) do
    "#{Date.to_iso8601(date)}T00:00:00Z"
  end

  defp datetime_on(date) do
    DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  end

  describe "open-calendar" do
    test "resets selection state so earlier days are not stuck disabled" do
      old_start = datetime_on(~D[2026-08-20])

      socket =
        init_socket(
          base_assigns(%{
            start_date_field: field(DateTime.to_iso8601(old_start)),
            end_date_field: end_field(DateTime.to_iso8601(old_start))
          })
        )

      {:noreply, socket} =
        DateRangePicker.handle_event("open-calendar", %{}, socket)

      assert socket.assigns.calendar? == true
      assert socket.assigns.state == :set_start
      assert socket.assigns.hover_range_end == nil
    end
  end

  describe "pick-date with min_nights: 0" do
    test "first click selects a single-day range for admin events" do
      socket = init_socket(base_assigns())

      {:noreply, socket} =
        DateRangePicker.handle_event(
          "pick-date",
          %{"date" => iso_date(~D[2026-08-10])},
          socket
        )

      assert DateTime.to_date(socket.assigns.range_start) == ~D[2026-08-10]
      assert DateTime.to_date(socket.assigns.range_end) == ~D[2026-08-10]
      assert socket.assigns.state == :set_end
    end

    test "clicking an earlier day while choosing end restarts the selection" do
      later = ~D[2026-08-20]
      earlier = ~D[2026-08-10]

      socket =
        init_socket(
          base_assigns(%{
            start_date_field: field(iso_date(later)),
            end_date_field: end_field(iso_date(later))
          })
        )

      {:noreply, socket} =
        DateRangePicker.handle_event("open-calendar", %{}, socket)

      {:noreply, socket} =
        DateRangePicker.handle_event(
          "pick-date",
          %{"date" => iso_date(later)},
          socket
        )

      assert socket.assigns.state == :set_end

      {:noreply, socket} =
        DateRangePicker.handle_event(
          "pick-date",
          %{"date" => iso_date(earlier)},
          socket
        )

      assert DateTime.to_date(socket.assigns.range_start) == earlier
      assert DateTime.to_date(socket.assigns.range_end) == earlier
    end
  end

  describe "update/2 while calendar is open" do
    test "preserves in-progress picks when parent re-renders with stale form values" do
      old_start = datetime_on(~D[2026-08-20])
      picked = ~D[2026-08-10]

      socket =
        init_socket(
          base_assigns(%{
            start_date_field: field(DateTime.to_iso8601(old_start)),
            end_date_field: end_field(DateTime.to_iso8601(old_start))
          })
        )

      {:noreply, socket} =
        DateRangePicker.handle_event("open-calendar", %{}, socket)

      {:noreply, socket} =
        DateRangePicker.handle_event(
          "pick-date",
          %{"date" => iso_date(picked)},
          socket
        )

      {:ok, socket} =
        DateRangePicker.update(
          base_assigns(%{
            start_date_field: field(DateTime.to_iso8601(old_start)),
            end_date_field: end_field(DateTime.to_iso8601(old_start))
          }),
          socket
        )

      assert DateTime.to_date(socket.assigns.range_start) == picked
      assert DateTime.to_date(socket.assigns.range_end) == picked
      assert socket.assigns.state == :set_end
    end

    test "reloads form values when the calendar is closed" do
      old_start = datetime_on(~D[2026-08-20])
      new_start = datetime_on(~D[2026-08-12])

      socket =
        init_socket(
          base_assigns(%{
            start_date_field: field(DateTime.to_iso8601(old_start)),
            end_date_field: end_field(DateTime.to_iso8601(old_start))
          })
        )

      {:ok, socket} =
        DateRangePicker.update(
          base_assigns(%{
            start_date_field: field(DateTime.to_iso8601(new_start)),
            end_date_field: end_field(DateTime.to_iso8601(new_start))
          }),
          socket
        )

      assert DateTime.to_date(socket.assigns.range_start) == ~D[2026-08-12]
      assert DateTime.to_date(socket.assigns.range_end) == ~D[2026-08-12]
      assert socket.assigns.state == :set_start
    end
  end

  describe "Pacific sale window anchoring" do
    test "anchors a freshly picked sale end date to 23:59:59 America/Los_Angeles" do
      socket =
        init_socket(
          base_assigns(%{
            timezone: "America/Los_Angeles",
            end_of_day?: true,
            is_range?: false,
            form: %{}
          })
        )

      {:noreply, socket} =
        DateRangePicker.handle_event("open-calendar", %{}, socket)

      {:noreply, socket} =
        DateRangePicker.handle_event(
          "pick-date",
          %{"date" => iso_date(~D[2026-08-14])},
          socket
        )

      {:noreply, _socket} =
        DateRangePicker.handle_event("close-calendar", %{}, socket)

      assert_receive {:updated_event, %{start_date: end_date}}

      # Aug 14 23:59:59 PDT is Aug 15 06:59:59 UTC — not midnight UTC on Aug 14,
      # which would expire the tier the evening of Aug 13 Pacific.
      assert end_date == ~U[2026-08-15 06:59:59Z]
    end

    test "anchors a freshly picked sale start date to midnight America/Los_Angeles" do
      socket =
        init_socket(
          base_assigns(%{
            timezone: "America/Los_Angeles",
            end_of_day?: false,
            is_range?: false,
            form: %{}
          })
        )

      {:noreply, socket} =
        DateRangePicker.handle_event("open-calendar", %{}, socket)

      {:noreply, socket} =
        DateRangePicker.handle_event(
          "pick-date",
          %{"date" => iso_date(~D[2026-08-14])},
          socket
        )

      {:noreply, _socket} =
        DateRangePicker.handle_event("close-calendar", %{}, socket)

      assert_receive {:updated_event, %{start_date: start_date}}

      assert start_date == ~U[2026-08-14 07:00:00Z]
    end
  end

  describe "Tahoe weekend rule (allow_saturdays: false)" do
    @friday ~D[2026-08-07]
    @saturday ~D[2026-08-08]
    @sunday ~D[2026-08-09]
    @monday ~D[2026-08-10]
    @thursday ~D[2026-08-13]
    @next_saturday ~D[2026-08-15]
    @next_sunday ~D[2026-08-16]

    defp cabin_assigns(overrides \\ %{}) do
      base_assigns(%{
        id: "tahoe_dates",
        min: @friday,
        today: @friday,
        max: ~D[2026-08-31],
        min_nights: 1,
        max_nights: 4,
        allow_saturdays: false
      })
      |> Map.merge(overrides)
    end

    defp pick(socket, %Date{} = date) do
      {:noreply, socket} =
        DateRangePicker.handle_event(
          "pick-date",
          %{"date" => iso_date(date)},
          socket
        )

      socket
    end

    defp hover(socket, %Date{} = date) do
      {:noreply, socket} =
        DateRangePicker.handle_event("cursor-move", iso_date(date), socket)

      socket
    end

    defp range_dates(socket) do
      start_date =
        case socket.assigns.range_start do
          nil -> nil
          dt -> DateTime.to_date(dt)
        end

      end_date =
        case socket.assigns.range_end do
          nil -> nil
          dt -> DateTime.to_date(dt)
        end

      {start_date, end_date}
    end

    test "ignores Saturday as a check-in (the old one-night exception is gone)" do
      socket = init_socket(cabin_assigns()) |> pick(@saturday)

      assert range_dates(socket) == {nil, nil}
      assert socket.assigns.state == :set_start
    end

    test "accepts Friday check-in and Sunday checkout as a full weekend span" do
      socket = init_socket(cabin_assigns()) |> pick(@friday)

      assert range_dates(socket) == {@friday, nil}
      assert socket.assigns.state == :set_end

      socket = pick(socket, @sunday)

      assert range_dates(socket) == {@friday, @sunday}
    end

    test "ignores Saturday checkout after a Friday check-in" do
      socket = init_socket(cabin_assigns()) |> pick(@friday) |> pick(@saturday)

      assert range_dates(socket) == {@friday, nil}
      assert socket.assigns.state == :set_end
    end

    test "accepts Monday checkout after Friday check-in (Friday-Sunday still in span)" do
      socket = init_socket(cabin_assigns()) |> pick(@friday) |> pick(@monday)

      assert range_dates(socket) == {@friday, @monday}
    end

    test "ignores Saturday checkout after Thursday check-in (Sunday missing)" do
      socket =
        init_socket(cabin_assigns()) |> pick(@thursday) |> pick(@next_saturday)

      assert range_dates(socket) == {@thursday, nil}
    end

    test "accepts Sunday checkout after Thursday check-in (full weekend in span)" do
      socket =
        init_socket(cabin_assigns()) |> pick(@thursday) |> pick(@next_sunday)

      assert range_dates(socket) == {@thursday, @next_sunday}
    end

    test "does not hover an incomplete Saturday span as a checkout preview" do
      socket = init_socket(cabin_assigns()) |> pick(@friday) |> hover(@saturday)

      assert socket.assigns.hover_range_end == nil

      socket = hover(socket, @sunday)

      assert DateTime.to_date(socket.assigns.hover_range_end) == @sunday
    end

    test "still allows Saturday check-in when allow_saturdays is true" do
      socket =
        init_socket(cabin_assigns(%{allow_saturdays: true}))
        |> pick(@saturday)

      assert range_dates(socket) == {@saturday, nil}

      socket = pick(socket, @sunday)

      assert range_dates(socket) == {@saturday, @sunday}
    end
  end

  describe "close-calendar" do
    test "normalizes reversed ranges and notifies the parent process" do
      socket =
        init_socket(
          base_assigns()
          |> Map.put(:form, %{})
        )

      {:noreply, socket} =
        DateRangePicker.handle_event("open-calendar", %{}, socket)

      {:noreply, socket} =
        DateRangePicker.handle_event(
          "pick-date",
          %{"date" => iso_date(~D[2026-08-12])},
          socket
        )

      {:noreply, socket} =
        DateRangePicker.handle_event(
          "pick-date",
          %{"date" => iso_date(~D[2026-08-14])},
          socket
        )

      {:noreply, socket} =
        DateRangePicker.handle_event("close-calendar", %{}, socket)

      assert socket.assigns.calendar? == false
      assert DateTime.to_date(socket.assigns.range_start) == ~D[2026-08-12]
      assert DateTime.to_date(socket.assigns.range_end) == ~D[2026-08-14]

      assert_receive {:updated_event,
                      %{
                        id: "event_date",
                        start_date: start_date,
                        end_date: end_date
                      }}

      assert DateTime.to_date(start_date) == ~D[2026-08-12]
      assert DateTime.to_date(end_date) == ~D[2026-08-14]
    end
  end
end
