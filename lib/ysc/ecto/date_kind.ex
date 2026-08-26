defmodule Ysc.Ecto.DateKind do
  @moduledoc """
  Parameterized Ecto type that records **how a date/time field must be converted**.

  Use this instead of a bare `:utc_datetime`, `:date`, or `:time` on fields whose
  timezone semantics matter. Credo `EX9003` requires it on ambiguous field names
  (`start_date`, `end_date`, `checkin_date`, …). Credo `EX9004` reads the kind
  from `schema.__schema__(:type, field)` and rejects the wrong conversions.

      field :start_date, Ysc.Ecto.DateKind, kind: :california_calendar_datetime
      field :checkin_date, Ysc.Ecto.DateKind, kind: :california_date
      field :start_time, Ysc.Ecto.DateKind, kind: :pacific_time
      field :start_date, Ysc.Ecto.DateKind, kind: :pacific_anchored_datetime
      field :published_on, Ysc.Ecto.DateKind, kind: :utc_instant

  Loaded values are still `%DateTime{}`, `%Date{}`, or `%Time{}` — this type
  only carries display/conversion metadata.

  ## Kinds

    * `:california_calendar_datetime` — Event `start_date` / `end_date`. Pacific
      wall-clock calendar days stored as DateTimes (typically midnight UTC of
      that day). Never `shift_zone`. Display with
      `YscWeb.DateDisplay.calendar_date/1` or `format_event_date_range/2`.
    * `:california_date` — Cabin check-in/out, seasons, blackouts, inventory
      days. `%Date{}` for California. Check-in is 3:00 PM Pacific. Never shift.
    * `:pacific_time` — Event / agenda `start_time` / `end_time`. `%Time{}` in
      Pacific wall-clock. Format as-is.
    * `:pacific_anchored_datetime` — Ticket-tier sale windows. Real UTC
      instants picked in the admin UI as Pacific days. Shift **to Pacific**
      (`format_pacific_date/1`, `format_sale_window_range/2`).
    * `:utc_instant` — Global timestamps (`published_on`, Stripe period ends,
      payments). Shift into the browser timezone
      (`format_date_in_zone/2` with `@timezone`).
    * `:naive_date` — Timezone-free calendar dates (date of birth, expense
      line dates). Format as-is; never shift.
  """

  use Ecto.ParameterizedType

  @kinds %{
    california_calendar_datetime: :utc_datetime,
    california_date: :date,
    pacific_time: :time,
    pacific_anchored_datetime: :utc_datetime,
    utc_instant: :utc_datetime,
    naive_date: :date
  }

  @shift_zone_policy %{
    california_calendar_datetime: :never,
    california_date: :never,
    pacific_time: :never,
    pacific_anchored_datetime: :pacific,
    utc_instant: :browser,
    naive_date: :never
  }

  @display_hint %{
    california_calendar_datetime:
      "YscWeb.DateDisplay.calendar_date/1 or format_event_date_range/2",
    california_date:
      "YscWeb.DateDisplay.format_date_long/1 or days_until_cabin_checkin/1",
    pacific_time: "format the %Time{} as-is (Pacific wall-clock)",
    pacific_anchored_datetime:
      "YscWeb.DateDisplay.format_pacific_date/1 or format_sale_window_range/2",
    utc_instant: "YscWeb.DateDisplay.format_date_in_zone/2 with @timezone",
    naive_date: "YscWeb.DateDisplay.format_date_long/1 (no timezone)"
  }

  @doc "Known kind atoms."
  def kinds, do: Map.keys(@kinds)

  @doc "Whether `kind` is a declared date kind."
  def valid_kind?(kind), do: Map.has_key?(@kinds, kind)

  @doc "Underlying Ecto primitive for `kind`."
  def underlying(kind) when is_atom(kind), do: Map.fetch!(@kinds, kind)

  @doc """
  Timezone conversion policy for `kind`.

  * `:never` — do not `shift_zone`
  * `:pacific` — shift to `America/Los_Angeles`
  * `:browser` — shift to LiveSocket `@timezone` (Pacific fallback)
  """
  def shift_zone_policy(kind) when is_atom(kind),
    do: Map.fetch!(@shift_zone_policy, kind)

  @doc "Human-readable display helper for Credo messages."
  def display_hint(kind) when is_atom(kind), do: Map.fetch!(@display_hint, kind)

  @impl true
  def init(opts) do
    kind = Keyword.get(opts, :kind)

    cond do
      kind in [nil, ""] ->
        raise ArgumentError, """
        Ysc.Ecto.DateKind requires `kind:`. Example:

            field :start_date, Ysc.Ecto.DateKind, kind: :california_calendar_datetime

        Valid kinds: #{kinds() |> Enum.sort() |> Enum.map_join(", ", &inspect/1)}
        """

      not valid_kind?(kind) ->
        raise ArgumentError,
              "unknown Ysc.Ecto.DateKind kind: #{inspect(kind)}. " <>
                "Valid kinds: #{kinds() |> Enum.sort() |> Enum.map_join(", ", &inspect/1)}"

      true ->
        %{kind: kind}
    end
  end

  @impl true
  def type(%{kind: kind}), do: underlying(kind)

  @impl true
  def cast(value, %{kind: kind}), do: Ecto.Type.cast(underlying(kind), value)

  @impl true
  def load(value, _loader, %{kind: kind}),
    do: Ecto.Type.load(underlying(kind), value)

  @impl true
  def dump(value, _dumper, %{kind: kind}),
    do: Ecto.Type.dump(underlying(kind), value)

  @impl true
  def embed_as(_format, _params), do: :self

  @impl true
  def equal?(left, right, %{kind: kind}),
    do: Ecto.Type.equal?(underlying(kind), left, right)
end
