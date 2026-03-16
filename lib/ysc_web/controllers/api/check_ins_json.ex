defmodule YscWeb.Api.CheckInsJSON do
  @moduledoc """
  JSON rendering for check-in API responses.
  """

  def show(%{check_in: check_in}) do
    %{
      data: %{
        id: to_string(check_in.id),
        checked_in_at:
          check_in.checked_in_at && DateTime.to_iso8601(check_in.checked_in_at),
        rules_agreed: check_in.rules_agreed,
        booking_ids: Enum.map(check_in.bookings || [], &to_string(&1.id)),
        vehicles:
          Enum.map(check_in.check_in_vehicles || [], fn v ->
            %{
              id: to_string(v.id),
              type: v.type,
              color: v.color,
              make: v.make
            }
          end)
      }
    }
  end
end
