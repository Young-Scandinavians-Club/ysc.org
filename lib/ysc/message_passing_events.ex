defmodule Ysc.MessagePassingEvents do
  @moduledoc """
  Message passing events for pub/sub notifications.

  Defines event structs for various domain events that are published
  through the pub/sub system for decoupled communication.
  """
  defmodule AgendaAdded do
    @moduledoc false
    defstruct agenda: nil
  end

  defmodule AgendaDeleted do
    @moduledoc false
    defstruct agenda: nil
  end

  defmodule AgendaUpdated do
    @moduledoc false
    defstruct agenda: nil
  end

  defmodule AgendaRepositioned do
    @moduledoc false
    defstruct agenda: nil
  end

  defmodule AgendaItemDeleted do
    @moduledoc false
    defstruct agenda_item: nil
  end

  defmodule AgendaItemRepositioned do
    @moduledoc false
    defstruct agenda_item: nil
  end

  defmodule AgendaItemAdded do
    @moduledoc false
    defstruct agenda_item: nil
  end

  defmodule AgendaItemUpdated do
    @moduledoc false
    defstruct agenda_item: nil
  end

  defmodule EventAdded do
    @moduledoc false
    defstruct event: nil
  end

  defmodule EventUpdated do
    @moduledoc false
    defstruct event: nil
  end

  defmodule EventDeleted do
    @moduledoc false
    defstruct event: nil
  end

  defmodule TicketTierAdded do
    @moduledoc false
    defstruct ticket_tier: nil
  end

  defmodule TicketTierUpdated do
    @moduledoc false
    defstruct ticket_tier: nil
  end

  defmodule TicketTierDeleted do
    @moduledoc false
    defstruct ticket_tier: nil
  end

  defmodule TicketCreated do
    @moduledoc false
    defstruct ticket: nil
  end

  defmodule CheckoutSessionExpired do
    @moduledoc false
    defstruct ticket_order: nil, user_id: nil, event_id: nil
  end

  defmodule CheckoutSessionCancelled do
    @moduledoc false
    defstruct ticket_order: nil, user_id: nil, event_id: nil, reason: nil
  end

  defmodule TicketAvailabilityUpdated do
    @moduledoc false
    defstruct event_id: nil
  end

  defmodule TicketReservationCreated do
    @moduledoc false
    defstruct ticket_reservation: nil
  end

  defmodule TicketReservationFulfilled do
    @moduledoc false
    defstruct ticket_reservation: nil
  end

  defmodule TicketReservationCancelled do
    @moduledoc false
    defstruct ticket_reservation: nil
  end
end
