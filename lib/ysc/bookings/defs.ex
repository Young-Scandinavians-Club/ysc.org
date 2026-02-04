defmodule Ysc.Bookings.BookingProperty do
  @moduledoc """
  Booking property enum.
  """
  use EctoEnum, type: :booking_property, enums: [:tahoe, :clear_lake]
end

defmodule Ysc.Bookings.BookingMode do
  @moduledoc """
  Booking mode enum (room, day, buyout, etc.)
  """
  use EctoEnum, type: :booking_mode, enums: [:room, :day, :buyout]
end

defmodule Ysc.Bookings.PriceUnit do
  @moduledoc """
  Price unit enum for different pricing models.

  - per_person_per_night: Tahoe room bookings
  - per_guest_per_day: Clear Lake day bookings (no rooms)
  - buyout_fixed: Fixed price for buyouts
  """
  use EctoEnum,
    type: :price_unit,
    enums: [:per_person_per_night, :per_guest_per_day, :buyout_fixed]
end

defmodule Ysc.Bookings.BookingStatus do
  @moduledoc """
  Booking status enum.

  - draft: Initial state, not yet held
  - hold: Inventory is held, waiting for payment
  - complete: Payment received, booking confirmed
  - refunded: Booking was refunded
  - canceled: Booking was canceled
  """
  use EctoEnum,
    type: :booking_status,
    enums: [:draft, :hold, :complete, :refunded, :canceled]
end
