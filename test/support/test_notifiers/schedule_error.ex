defmodule Ysc.TestNotifiers.ScheduleError do
  @moduledoc false
  # Used by BookingLockerTest to force `schedule_email/8` to return an error
  # tuple while exercising BookingLocker's confirmation-email scheduling path.

  def schedule_email(a, b, c, d, e, f, g),
    do: schedule_email(a, b, c, d, e, f, g, nil)

  def schedule_email(_, _, _, _, _, _, _, _),
    do: {:error, :coverage_schedule_failed}
end
