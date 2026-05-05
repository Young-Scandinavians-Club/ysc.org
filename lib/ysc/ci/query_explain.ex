defmodule Ysc.Ci.QueryExplain do
  @moduledoc false

  import Ecto.Query

  alias Ysc.Tickets.TicketOrder

  @doc false
  def ticket_orders_pending_timeout_batch_query do
    now = DateTime.utc_now()

    from(t in TicketOrder,
      where: t.status == :pending and t.expires_at < ^now,
      order_by: [asc: t.expires_at],
      limit: 100
    )
  end
end
