defmodule Ysc.Events.TicketOrderStatus do
  @moduledoc """
  Ticket order status enum.
  """
  use EctoEnum,
    type: :ticket_order_status,
    enums: [:pending, :completed, :cancelled, :expired]
end

defmodule Ysc.Events.TicketStatus do
  @moduledoc """
  Ticket status enum.
  """
  use EctoEnum,
    type: :ticket_status,
    enums: [:pending, :confirmed, :cancelled, :expired]
end

defmodule Ysc.Events.TicketTierType do
  @moduledoc """
  Ticket tier type enum.
  """
  use EctoEnum, type: :ticket_tier_type, enums: [:free, :paid, :donation]
end

defmodule Ysc.Events.EventState do
  @moduledoc """
  Event state enum.
  """
  use EctoEnum,
    type: :event_state,
    enums: [:draft, :scheduled, :published, :cancelled, :deleted]
end
