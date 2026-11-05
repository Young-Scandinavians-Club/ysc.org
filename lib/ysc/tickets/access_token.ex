defmodule Ysc.Tickets.AccessToken do
  @moduledoc """
  Signed tokens for opening tickets without signing in.

  Ticket emails go to people who may have no YSC login (volunteers, guests a
  member bought a ticket for). Each email links to `/t/:token`, which shows the
  QR code and the "Add to wallet" buttons for just the tickets the token covers.

  A token covers one of:

    * `{:order, order_id}` - every ticket in an order (purchaser's email)
    * `{:tickets, ticket_ids}` - a fixed set of tickets in one order (a guest's email)
    * `{:ticket, ticket_id}` - a single ticket (QR image and wallet downloads)

  Tokens carry no authority beyond reading those tickets; whether a ticket can
  still be used is decided at scan time against the database, exactly as for the
  in-app QR code.
  """

  @salt "ticket_access_v1"
  @max_age_seconds 400 * 24 * 60 * 60

  @type payload ::
          {:order, String.t()}
          | {:tickets, [String.t()]}
          | {:ticket, String.t()}

  @doc "Signs a token covering every ticket in the order."
  def sign_order(order_id), do: sign({:order, order_id})

  @doc "Signs a token covering exactly the given tickets."
  def sign_tickets([ticket_id]), do: sign({:ticket, ticket_id})

  def sign_tickets(ticket_ids) when is_list(ticket_ids),
    do: sign({:tickets, Enum.sort(ticket_ids)})

  @doc "Signs a token covering a single ticket."
  def sign_ticket(ticket_id), do: sign({:ticket, ticket_id})

  @doc """
  Verifies a token.

  Returns `{:ok, payload}` or `{:error, :invalid}`.
  """
  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(YscWeb.Endpoint, @salt, token,
           max_age: @max_age_seconds
         ) do
      {:ok, {:order, id} = payload} when is_binary(id) -> {:ok, payload}
      {:ok, {:ticket, id} = payload} when is_binary(id) -> {:ok, payload}
      {:ok, {:tickets, ids} = payload} when is_list(ids) -> {:ok, payload}
      _ -> {:error, :invalid}
    end
  end

  def verify(_), do: {:error, :invalid}

  @doc """
  Verifies a token that must cover a single ticket and returns its id.

  Used by the QR image and wallet download endpoints, which are per ticket.
  """
  def verify_ticket(token) do
    case verify(token) do
      {:ok, {:ticket, ticket_id}} -> {:ok, ticket_id}
      _ -> {:error, :invalid}
    end
  end

  defp sign(payload), do: Phoenix.Token.sign(YscWeb.Endpoint, @salt, payload)
end
