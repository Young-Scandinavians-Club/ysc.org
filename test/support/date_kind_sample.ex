defmodule Ysc.Ecto.DateKindSample do
  @moduledoc false
  use Ecto.Schema

  schema "date_kind_samples" do
    field :start_date, Ysc.Ecto.DateKind, kind: :california_calendar_datetime
    field :checkin_date, Ysc.Ecto.DateKind, kind: :california_date
    field :start_time, Ysc.Ecto.DateKind, kind: :pacific_time
  end
end
