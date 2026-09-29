defmodule YscWeb.Components.CalendarMonth do
  @moduledoc """
  Shared month-grid state and navigation header for calendar LiveComponents.

  The availability calendar and date-range picker both render a Monday-start
  month grid plus prev / next / Today controls. Use `month_state/1` for the
  assign map and `<.calendar_month_nav>` for the header.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  @week_start_at :monday

  @doc """
  Builds the month assign used by calendar LiveComponents.

  Returns `%{date, month, week_rows}` where `month` is `"August 2026"` and
  `week_rows` is a list of 7-day lists covering the full weeks that overlap
  the month, starting Monday.

  ## Examples

      iex> state = YscWeb.Components.CalendarMonth.month_state(~D[2026-09-21])
      iex> state.month
      "September 2026"
      iex> hd(hd(state.week_rows))
      ~D[2026-08-31]
  """
  def month_state(%Date{} = date) do
    %{
      date: date,
      month: Calendar.strftime(date, "%B %Y"),
      week_rows: week_rows(date)
    }
  end

  @doc """
  Monday-start week rows covering every day of `date`'s month.
  """
  def week_rows(%Date{} = date) do
    first =
      date
      |> Date.beginning_of_month()
      |> Date.beginning_of_week(@week_start_at)

    last = date |> Date.end_of_month() |> Date.end_of_week(@week_start_at)
    Date.range(first, last) |> Enum.map(& &1) |> Enum.chunk_every(7)
  end

  @doc """
  True when `current_date` falls in the same calendar month as `today`.

  Returns `nil`/`false` when `today` is missing so the Today control stays
  enabled rather than crashing.
  """
  def showing_current_month?(current_date, today) do
    today &&
      Date.beginning_of_month(current_date) == Date.beginning_of_month(today)
  end

  @doc """
  Month label with previous / next / Today controls.

  Emits `prev-month`, `next-month`, and `today` to `target` (typically
  `@myself` in a LiveComponent).

  ## Examples

      <.calendar_month_nav
        id="calendar"
        current={@current}
        today={@today}
        target={@myself}
        class="mb-4"
        month_label_class="font-semibold text-lg"
      />
  """
  attr :id, :string, required: true

  attr :current, :map,
    required: true,
    doc: "Month state from `month_state/1` (`:date` and `:month`)"

  attr :today, Date, required: true
  attr :target, :any, required: true, doc: "LiveComponent CID (`@myself`)"

  attr :class, :any,
    default: nil,
    doc: "Extra classes on the header row (merged with flex layout)"

  attr :header_id, :string,
    default: nil,
    doc: "Optional DOM id on the header wrapper"

  attr :month_label_id, :string, doc: "Defaults to `{id}-month-label`"

  attr :month_label_class, :any,
    default: "font-semibold",
    doc: "Classes on the month/year label"

  def calendar_month_nav(assigns) do
    current_month? = showing_current_month?(assigns.current.date, assigns.today)

    assigns =
      assigns
      |> assign(:current_month?, current_month?)
      |> assign_new(:month_label_id, fn -> "#{assigns.id}-month-label" end)

    ~H"""
    <div id={@header_id} class={["flex justify-between items-center", @class]}>
      <button
        type="button"
        id={"#{@id}-prev-month"}
        phx-target={@target}
        phx-click="prev-month"
        class="p-1.5 text-zinc-400 hover:text-zinc-500 transition duration-300"
        aria-label="Previous month"
      >
        <.icon name="hero-arrow-left" />
      </button>

      <div class="flex flex-col items-center gap-1">
        <div id={@month_label_id} class={@month_label_class}>
          {@current.month}
        </div>
        <button
          id={"#{@id}-go-to-today"}
          type="button"
          phx-target={@target}
          phx-click="today"
          disabled={@current_month?}
          class={[
            "inline-flex items-center gap-1.5 px-3 py-1 text-xs font-semibold border rounded-md focus:outline-hidden focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
            if(@current_month?,
              do:
                "text-zinc-400 bg-zinc-50 border-zinc-200 cursor-not-allowed opacity-60",
              else: "text-zinc-700 bg-zinc-100 hover:bg-zinc-200 border-zinc-300"
            )
          ]}
          aria-label={
            if @current_month? do
              "Already showing #{Calendar.strftime(@today, "%B %Y")}"
            else
              "Go to current month, #{Calendar.strftime(@today, "%B %Y")}"
            end
          }
        >
          <.icon name="hero-calendar-days" class="w-4 h-4" aria-hidden="true" />
          Today
        </button>
      </div>

      <button
        type="button"
        id={"#{@id}-next-month"}
        phx-target={@target}
        phx-click="next-month"
        class="p-1.5 text-zinc-400 hover:text-zinc-500 transition duration-300"
        aria-label="Next month"
      >
        <.icon name="hero-arrow-right" />
      </button>
    </div>
    """
  end
end
