defmodule YscWeb.TicketUserMessages do
  @moduledoc false

  def leave_unpaid_checkout_button do
    "Leave without tickets"
  end

  def leave_unpaid_checkout_busy do
    "Leaving..."
  end

  def leave_unpaid_checkout_confirm do
    trim("""
    Leave without tickets? These tickets will go back on sale. Your tickets are not confirmed yet.
    """)
  end

  def leave_unpaid_checkout_toast do
    trim("""
    You left without tickets. Those tickets are available again if you want to start over.
    """)
  end

  defp trim(string), do: String.trim(string)
end
