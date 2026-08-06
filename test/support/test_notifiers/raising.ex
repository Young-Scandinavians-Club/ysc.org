defmodule Ysc.TestNotifiers.Raising do
  @moduledoc false
  # Used by BookingLockerTest to force `schedule_email/8` to raise while
  # exercising BookingLocker's confirmation-email rescue branch.

  def schedule_email(_, _, _, _, _, _, _, _) do
    raise "boom - coverage test"
  end
end
