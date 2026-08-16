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
